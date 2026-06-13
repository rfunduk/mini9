package engine

import mrb "lib:mruby"
import rl "lib:raylib"


// RUBY FUNCTION: clear(color) -> configures the clear color
// @engine_method: name="clear", aspec=ARGS_REQ(1)
ruby_clear :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color_val: mrb.Value
	mrb.get_args(state, "o", &color_val)

	color: rl.Color = rl.Color{0, 0, 0, 0}
	if color_val != mrb.NIL {
		color_ptr := extract_native(rl.Color, color_val)
		if color_ptr != nil { color = color_ptr^ }
	}

	if g.phase == .INIT {
		g.clear_color = color
	} else if g.phase == .DRAW {
		rl.ClearBackground(color)
	}

	return mrb.NIL
}

// RUBY FUNCTION: assert(yn, message) -> crash the game if yn is falsy
// @engine_method: name="assert", aspec=ARGS_ARG(1,1)
ruby_assert :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	yn_val, msg_val: mrb.Value
	mrb.get_args(state, "o|o", &yn_val, &msg_val)

	fail := yn_val == mrb.NIL || yn_val == mrb.FALSE
	if fail {
		msg: string
		if msg_val == mrb.NIL {
			msg = "Error"
		} else {
			msg_str := mrb.obj_as_string(state, msg_val)
			msg = string(mrb.str_to_cstr(state, msg_str))
		}
		return mrb.raise_error(state, "RuntimeError", "Assertion error: %s", msg)
	}
	return mrb.NIL
}

// RUBY FUNCTION: time() -> game time in seconds (scaled by timescale)
// @engine_method: name="time", aspec=ARGS_NONE
ruby_time :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return mrb.word_boxing_float_value(state, g.game_time)
}

// RUBY FUNCTION: walltime() -> wall-clock time in seconds since the game started
// @engine_method: name="walltime", aspec=ARGS_NONE
ruby_walltime :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return mrb.word_boxing_float_value(state, rl.GetTime())
}

// RUBY FUNCTION: dt() -> fixed timestep delta in seconds
// @engine_method: name="dt", aspec=ARGS_NONE
ruby_dt :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return mrb.word_boxing_float_value(state, f64(FIXED_DT))
}

// RUBY FUNCTION: timescale(n=nil) -> sets game timescale (>=0), returns current
// @engine_method: name="timescale", aspec=ARGS_OPT(1)
ruby_timescale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	n: f64
	argc := mrb.get_args(state, "|f", &n)

	if argc == 0 { return mrb.word_boxing_float_value(state, f64(g.timescale)) }

	if n < 0 {
		return mrb.raise_error(state, "ArgumentError", "timescale must be >= 0")
	}

	g.timescale = f32(n)
	return mrb.word_boxing_float_value(state, f64(g.timescale))
}

// RUBY FUNCTION: quit() -> exits the game
// @engine_method: name="quit", aspec=ARGS_NONE
ruby_quit :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	g.run = false
	return mrb.NIL
}

// RUBY FUNCTION: resolution(w, h) -> sets game resolution during INIT, returns current resolution otherwise
// @engine_method: name="resolution", aspec=ARGS_OPT(2)
ruby_resolution :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	w, h: f64
	argc := mrb.get_args(state, "|f|f", &w, &h)

	if argc == 0 || g.phase != .INIT {
		return create_vector2(g.resolution)
	}

	if argc == 1 { h = w }

	g.resolution = {f32(w), f32(h)}
	return create_vector2(g.resolution)
}

// RUBY FUNCTION: cursor(enabled) -> enables/disables cursor, returns current state
// @engine_method: name="cursor", aspec=ARGS_OPT(1)
ruby_cursor :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	enabled_val: mrb.Value
	argc := mrb.get_args(state, "|b", &enabled_val)

	if argc == 0 { return g.cursor ? mrb.TRUE : mrb.FALSE }
	g.cursor = mrb.boolean(enabled_val)

	if g.phase == .UPDATE {
		set_cursor_visible(g.cursor)
	}

	return g.cursor ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: fullscreen(yn=nil) -> sets fullscreen mode, or returns current state
// @engine_method: name="fullscreen", aspec=ARGS_OPT(1)
ruby_fullscreen :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	when ODIN_OS == .JS { return mrb.FALSE }

	yn_val: mrb.Value
	argc := mrb.get_args(state, "|b", &yn_val)
	yn := mrb.boolean(yn_val)

	current := rl.IsWindowFullscreen()
	if argc == 0 { return current ? mrb.TRUE : mrb.FALSE }

	// destructive setup: silently ignore on reload so re-running main.rb doesn't re-toggle.
	if g.phase == .RELOAD { return current ? mrb.TRUE : mrb.FALSE }

	if (current && !yn) || (!current && yn) {
		rl.ToggleFullscreen()
		calculate_screen_layout()
	}

	return yn ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: fps(target_fps) -> sets target FPS during INIT, returns current FPS otherwise
// @engine_method: name="fps", aspec=ARGS_OPT(1)
ruby_fps :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	target_fps: i32
	argc := mrb.get_args(state, "|i", &target_fps)

	if argc == 0 { return mrb.boxing_int_value(state, rl.GetFPS()) }

	// destructive setup: silently ignore on reload so re-running main.rb is a no-op.
	if g.phase == .RELOAD { return mrb.boxing_int_value(state, g.fps) }

	if g.phase != .INIT {
		return mrb.raise_error(state, "RuntimeError", "fps() can only be set during INIT phase")
	}
	if target_fps < 5 {
		return mrb.raise_error(state, "ArgumentError", "FPS must be >= 5")
	}

	g.fps = target_fps
	return mrb.boxing_int_value(state, g.fps)
}

// RUBY FUNCTION: web?() -> returns true if running on web platform
// @engine_method: name="web?", aspec=ARGS_NONE
ruby_web :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	when ODIN_OS == .JS { return mrb.TRUE } else { return mrb.FALSE }
}

// RUBY FUNCTION: reloading?() -> true while game code is being re-run by a hot reload
// @engine_method: name="reloading?", aspec=ARGS_NONE
ruby_reloading :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return g.phase == .RELOAD ? mrb.TRUE : mrb.FALSE
}
