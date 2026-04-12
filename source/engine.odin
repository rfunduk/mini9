package engine

import "core:log"
import "core:math/ease"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"


_engine_init :: proc(rom_data: ^Rom_Data) {
	global_context = context
	g = new(Engine_Memory)

	g^ = Engine_Memory {
		rom_data            = rom_data,
		title               = strings.clone(""),
		debug               = ENGINE_DEBUG,
		metrics             = false,
		resolution          = rl.Vector2{128, 128},
		clear_color         = rl.Color{0, 0, 0, 255},
		fps                 = 60,
		run                 = true,
		flux                = ease.flux_init(f32, 128),
		phase               = .INIT,
		cursor              = true,
		fixed_dt            = 1.0 / 60.0, // 16.67ms fixed timestep
		accumulator         = 0.0,
		max_frame_time      = 0.25, // cap at 250ms (prevents spiral of death)
		deferred_textures   = make([dynamic]Texture_Load_Data),
		deferred_fonts      = make([dynamic]FontLoadData),
		cameras             = make([dynamic]^Camera_Instance),
		shake_instances     = make([dynamic]^Shake_Instance),
		sounds              = make([dynamic]^Sound),
		music               = make([dynamic]^Music),
		pending_tweens      = make([dynamic]^Tween_Instance),
		pressed_this_frame  = make(map[i32]bool),
		released_this_frame = make(map[i32]bool),
		next_shake_id       = 1,
	}

	g.camera.zoom = 1

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
	g.camera = {
		zoom   = 1,
		target = g.resolution / 2,
		offset = g.resolution / 2,
	}

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

	rl.SetConfigFlags({.VSYNC_HINT})

	init_game_window()

	rl.SetTargetFPS(g.fps)
	rl.SetExitKey(nil)

	g.render_texture = rl.LoadRenderTexture(i32(g.resolution.x), i32(g.resolution.y))
	rl.SetTextureFilter(g.render_texture.texture, .POINT)

	// calculate initial screen layout
	calculate_screen_layout()

	// load deferred assets
	load_deferred_fonts()
	load_deferred_textures()

	// apply cursor state set during initialization
	set_cursor_visible(g.cursor)
}

_engine_update :: proc() {
	ensure_audio_initialized()

	// fixed timestep implementation
	frame_time := rl.GetFrameTime()

	// clamp frame time to prevent spiral of death
	if frame_time > g.max_frame_time {
		frame_time = g.max_frame_time
	}

	g.accumulator += frame_time

	clear(&g.pressed_this_frame)
	clear(&g.released_this_frame)

	// run fixed timestep updates until we've consumed all accumulated time
	for g.accumulator >= g.fixed_dt {
		g.frame_count += 1

		g.phase = .UPDATE
		reset_camera_system()

		// update systems with fixed timestep
		ease.flux_update(&g.flux, f64(g.fixed_dt))
		start_pending_tweens()

		// process events first, before update
		call_user_events()

		// user update gets consistent fixed timestep
		call_user_update(g.fixed_dt)

		// only update audio systems if audio is initialized
		if g.audio_initialized {
			update_audio_system(g.fixed_dt)
			update_music_system(g.fixed_dt)
		}

		update_shake_system()
		step_physics(g.fixed_dt)

		g.accumulator -= g.fixed_dt
	}

	g.phase = .DRAW
	rl.BeginDrawing()

	rl.BeginTextureMode(g.render_texture)

	rl.BeginMode2D(g.camera)
	call_user_draw()
	rl.EndMode2D()

	// draw ui elements
	// TODO -- we should maybe have a g.ui_camera which should consider cameras just like
	//         the reguar mode does except like camera(..., layer: :ui) or something
	rl.BeginMode2D({zoom = 1})
	call_user_ui()
	rl.EndMode2D()

	rl.EndTextureMode()

	// now we take the completed frame and handle
	// drawing it to the actual surface
	rl.BeginMode2D({zoom = 1})

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
	}

	rl.EndMode2D()
	rl.EndDrawing()

	if g.metrics { collect_metrics() }

	free_all(context.temp_allocator)
}

_engine_shutdown :: proc() {
	// shutdown mruby
	if g.mrb_ctx != nil {
		mrb.ccontext_free(g.mrb_state, g.mrb_ctx)
		g.mrb_ctx = nil
	}
	if g.mrb_state != nil {
		mrb.close(g.mrb_state)
		g.mrb_state = nil
	}

	rl.CloseAudioDevice()
	rl.UnloadRenderTexture(g.render_texture)
	ease.flux_destroy(g.flux)

	// cleanup dynamic arrays
	delete(g.cameras)
	delete(g.deferred_fonts)
	delete(g.deferred_textures)
	delete(g.shake_instances)
	delete(g.sounds)
	delete(g.music)
	delete(g.pending_tweens)

	// cleanup maps
	delete(g.pressed_this_frame)
	delete(g.released_this_frame)
	cleanup_vector2()
	cleanup_physics()

	// cleanup strings
	delete(g.title)

	// cleanup global type map
	delete(NATIVE_TO_MRUBY_TYPE)

	rom_data_free(g.rom_data)
	free(g)
}
