package engine

import "core:log"
import "core:math/ease"
import "core:strings"
import mrb "lib:mruby"
import rl "lib:raylib"
import rlgl "lib:raylib/rlgl"

@(private = "file")
accumulator: f32

_engine_init :: proc(rom_data: ^Rom_Data, rom_path: string = "") {
	global_context = context
	g = new(Engine_Memory)

	g^ = Engine_Memory {
		rom_data    = rom_data,
		rom_path    = strings.clone(rom_path),
		title       = strings.clone("mini9"),
		metrics     = false,
		resolution  = rl.Vector2{128, 128},
		clear_color = rl.Color{0, 0, 0, 255},
		fps         = 60,
		run         = true,
		flux        = ease.flux_init(f32, 128),
		phase       = .INIT,
		cursor      = true,
		timescale   = 1.0,
	}

	input_edge_queue = make(map[i32]Key_Edges)
	input_current_edges = make(map[i32]Edge_Kind)

	rl.SetTraceLogLevel(.ERROR)

	when ODIN_OS == .JS {
		// web builds: audio will be initialized on first user input
		g.audio_initialized = false
	} else {
		// native builds: initialize audio immediately
		rl.InitAudioDevice()
		g.audio_initialized = true
	}

	// default camera
	g.camera = default_camera()

	// initialize mruby system & load user code
	g.mrb_state = mrb.open()
	if g.mrb_state == nil {
		log.errorf("Failed to set up Ruby VM")
		panic("EXITING")
	}
	g.mrb_ctx = mrb.ccontext_new(g.mrb_state)
	if g.mrb_ctx == nil {
		log.errorf("Failed to set up Ruby VM context")
		panic("EXITING")
	}
	cache_symbols()
	engine_init_ruby_api()
	load_main_rb()
	determine_game_callbacks()
	apply_metadata_title()

	// WINDOW_HIGHDPI only on macOS (retina). Browser owns DPI;
	// Linux/Windows double-scale dest_rect under HIGHDPI w/ raylib 6.0.
	flags: rl.ConfigFlags = {.VSYNC_HINT}
	when ODIN_OS == .Darwin { flags += {.WINDOW_HIGHDPI} }
	rl.SetConfigFlags(flags)

	init_game_window()

	rl.SetTargetFPS(g.fps)
	rl.SetExitKey(nil)

	g.render_texture = rl.LoadRenderTexture(i32(g.resolution.x), i32(g.resolution.y))

	if !rl.IsWindowReady() || g.render_texture.texture.id == 0 {
		log.errorf("GL context not viable")
		panic("EXITING")
	}

	rl.SetTextureFilter(g.render_texture.texture, .POINT)

	// custom render batch so we can inspect drawCounter for metrics
	g.batch = rlgl.LoadRenderBatch(1, rlgl.DEFAULT_BATCH_BUFFER_ELEMENTS)
	rlgl.SetRenderBatchActive(&g.batch)

	// calculate initial screen layout
	calculate_screen_layout()

	// load deferred assets — fonts first so their glyph images exist,
	// then textures; finally pack them all into one atlas.
	load_deferred_fonts()
	load_deferred_textures()
	pack_atlas()

	// apply cursor state set during initialization
	set_cursor_visible(g.cursor)
}

_engine_update :: proc() {
	ensure_audio_initialized()

	// fixed timestep implementation
	frame_time := rl.GetFrameTime()

	// clamp frame time to prevent spiral of death
	if frame_time > MAX_FRAME_TIME {
		frame_time = MAX_FRAME_TIME
	}

	accumulator += frame_time * g.timescale

	g.phase = .UPDATE

	// sweep raylib input edges into per-key queues every wall-frame —
	// edges are wall-frame-edge-triggered, so polling them from the scaled
	// loop would drop edges under low timescale or high refresh rates
	sweep_input_edges()

	// audio + music pump must run at wall-cadence — UpdateMusicStream
	// keeps raylib's decode buffer fed; under timescale=0 the scaled loop
	// stops entirely and music would starve and cut out. Fades use real
	// frame time so audio effects measured in seconds stay wall-time.
	if g.audio_initialized {
		update_audio_system(frame_time)
		update_music_system(frame_time)
	}

	// Advance cooperative tasks at wall cadence (outside the fixed loop) so an
	// AI/gen task still progresses when timescale=0 pauses the scaled loop.
	// Own arena bound: resuming fibers allocates ruby values that must not pin
	// live objects into the draw phase. The fiber's suspended stack is marked
	// via $tasks, so arena restore only drops this tick's temporaries.
	{
		task_arena := mrb.gc_arena_save(g.mrb_state)
		defer mrb.gc_arena_restore(g.mrb_state, task_arena)
		call_user_tasks()
	}

	// run fixed timestep updates until we've consumed all accumulated time
	for accumulator >= FIXED_DT {
		g.frame_count += 1
		g.game_time += f64(FIXED_DT)

		advance_input_edges()
		reset_camera_system()

		// Bound the mruby GC arena for the whole tick. Engine-internal
		// allocations (e.g. Vector2s from sync_dynamic_bodies) would
		// otherwise pile up in the arena and pin live objects forever.
		// Anything that must survive past this tick keeps its own explicit
		// gc_register (e.g. obj.pos).
		arena_idx := mrb.gc_arena_save(g.mrb_state)
		defer mrb.gc_arena_restore(g.mrb_state, arena_idx)

		// update systems with fixed timestep
		ease.flux_update(&g.flux, f64(FIXED_DT))
		start_pending_tweens()

		// process events first, before update
		call_user_events()

		// fire any timers whose interval has elapsed
		update_timers()

		// integrate particle systems
		update_particles()

		// user update gets consistent fixed timestep
		call_user_update()

		update_shake_system()
		step_physics()

		accumulator -= FIXED_DT
	}

	g.phase = .DRAW
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	{
		// Bound the arena across the draw phase too. User draw callbacks that
		// allocate ruby-side values (Vector2, Rect, strings, etc.) via native
		// methods already self-manage at each ruby->native boundary, but
		// engine-internal drawing is pure odin and would otherwise leak.
		draw_arena_idx := mrb.gc_arena_save(g.mrb_state)
		defer mrb.gc_arena_restore(g.mrb_state, draw_arena_idx)

		rl.BeginTextureMode(g.render_texture)

		// draw_calls accumulates across flush points (EndMode2D + EndTextureMode each flush).
		// peek drawCounter just before each flush, sum. Baseline of 1/flush means count is
		// slightly inflated but stable — useful as relative metric.
		g.draw_calls = 0

		rl.BeginMode2D(g.camera)
		call_user_draw()
		g.draw_calls += i32(g.batch.drawCounter)
		rl.EndMode2D()

		// draw ui elements
		// TODO -- we should maybe have a g.ui_camera which should consider cameras just like
		//         the reguar mode does except like camera(..., layer: :ui) or something
		rl.BeginMode2D({zoom = 1})
		call_user_ui()
		g.draw_calls += i32(g.batch.drawCounter)
		rl.EndMode2D()

		rl.EndTextureMode()
	}

	{
		// now we take the completed frame and handle
		// drawing it to the actual surface.
		//
		// NOTE: NO BeginMode2D here — BeginDrawing() installs a screenScale
		// modelview (identity on non-HighDPI, scaleDPI on retina). A
		// BeginMode2D call would rlLoadIdentity and wipe that matrix, which
		// would make logical-coord draws render at the wrong scale on HighDPI.

		// draw game texture using pre-calculated layout
		rl.DrawTexturePro(
			texture = g.render_texture.texture,
			source = {0, 0, g.resolution.x, -g.resolution.y},
			dest = g.dest_rect,
			origin = {0, 0},
			rotation = 0,
			tint = rl.WHITE,
		)

		if g.metrics {
			draw_memory_graph()
			draw_fps_graph()
			draw_tweens_graph()
			draw_draws_graph()
			draw_bodies_graph()
		}
	}

	rl.EndDrawing()

	if g.metrics { collect_metrics() }

	mrb.incremental_gc(g.mrb_state)
	free_all(context.temp_allocator)
}

_engine_shutdown :: proc() {
	// close mruby first — mrb_close runs finalizers synchronously; they may
	// return native ptrs to subsystem pools (e.g. Vector2 slab) or reference
	// subsystem state. cleanup_* below only tears down Odin-side arrays +
	// resources, none of it calls into mruby, so finalizers must fire first.
	if g.mrb_ctx != nil {
		mrb.ccontext_free(g.mrb_state, g.mrb_ctx)
		g.mrb_ctx = nil
	}
	if g.mrb_state != nil {
		mrb.close(g.mrb_state)
		g.mrb_state = nil
	}

	engine_cleanup_ruby_api()

	rl.CloseAudioDevice()
	// custom batch intentionally not unloaded here — raylib's CloseWindow
	// tears down rlgl state; explicit unload races with that and corrupts heap
	rl.UnloadRenderTexture(g.render_texture)
	ease.flux_destroy(g.flux)

	// cleanup strings
	delete(g.title)
	delete(g.rom_path)

	// cleanup global type map
	delete(NATIVE_TO_MRUBY_TYPE)

	rom_data_free(g.rom_data)
	free(g)
}
