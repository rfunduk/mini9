package engine

import "core:log"
import "core:os"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"


// RUBY FUNCTION: clear(color) -> configures the clear color
// @engine_method: name="clear", arity=1
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
// @engine_method: name="assert", arity=2
ruby_assert :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	yn_val, msg_val: mrb.Value
	mrb.get_args(state, "o|o", &yn_val, &msg_val)

	msg: string
	if msg_val == mrb.NIL {
		msg = "Error"
	} else {
		msg_str := mrb.obj_as_string(state, msg_val)
		emsg := strings.clone_from_cstring(mrb.str_to_cstr(state, msg_str)) or_else "Unknown Error"
		msg = emsg
	}

	fail := yn_val == mrb.NIL || yn_val == mrb.FALSE
	if fail {
		log.errorf("Assertion error:\n\n%s\n\n", msg)
		os.exit(1)
	}
	return mrb.NIL
}

// RUBY FUNCTION: time() -> time in seconds since the game started
// @engine_method: name="time", arity=0
ruby_time :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return mrb.word_boxing_float_value(state, rl.GetTime())
}

// RUBY FUNCTION: quit() -> exits the game
// @engine_method: name="quit", arity=0
ruby_quit :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	g.run = false
	return mrb.NIL
}

// RUBY FUNCTION: resolution(w, h) -> sets game resolution during INIT, returns current resolution otherwise
// @engine_method: name="resolution", arity=-1
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

// RUBY FUNCTION: title(title) -> sets window title
// @engine_method: name="title", arity=1
ruby_title :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	title_val: mrb.Value
	mrb.get_args(state, "o", &title_val)

	str_obj := mrb.obj_as_string(state, title_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	g.title = strings.clone_from_cstring(c_str)
	return mrb.NIL
}

// RUBY FUNCTION: cursor(enabled) -> enables/disables cursor, returns current state
// @engine_method: name="cursor", arity=-1
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
// @engine_method: name="fullscreen", arity=-1
ruby_fullscreen :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	when ODIN_OS == .JS { return mrb.FALSE }

	yn_val: mrb.Value
	argc := mrb.get_args(state, "|b", &yn_val)
	yn := mrb.boolean(yn_val)

	current := rl.IsWindowFullscreen()
	if argc == 0 { return current ? mrb.TRUE : mrb.FALSE }

	if (current && !yn) || (!current && yn) {
		rl.ToggleFullscreen()
		calculate_screen_layout()
	}

	return yn ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: fps(target_fps) -> sets target FPS during INIT, returns current FPS otherwise
// @engine_method: name="fps", arity=-1
ruby_fps :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	target_fps: i32
	argc := mrb.get_args(state, "|i", &target_fps)

	if argc == 0 { return mrb.boxing_int_value(state, rl.GetFPS()) }

	if g.phase != .INIT {
		log.errorf("fps() can only be set during INIT phase")
		os.exit(1)
	}
	if target_fps < 5 {
		log.errorf("FPS must be >= 5")
		os.exit(1)
	}

	g.fps = target_fps
	return mrb.boxing_int_value(state, g.fps)
}

// RUBY FUNCTION: web?() -> returns true if running on web platform
// @engine_method: name="web?", arity=0
ruby_web :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	when ODIN_OS == .JS { return mrb.TRUE } else { return mrb.FALSE }
}
