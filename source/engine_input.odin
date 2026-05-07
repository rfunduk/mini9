package engine

import mrb "lib:mruby"
import rl "lib:raylib"

@(private = "file")
cached_mouse_frame: u32
@(private = "file")
cached_mouse_world: rl.Vector2
@(private = "file")
cached_mouse_ui: rl.Vector2

@(private = "file")
cached_keys_frame: u32
@(private = "file")
cached_keys: [10]rl.KeyboardKey

// shared with engine.odin (cleared per render frame in the main loop)
pressed_this_frame: map[i32]bool
released_this_frame: map[i32]bool

// RUBY FUNCTION: _key_down_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_down_impl", aspec=ARGS_ARG(1,1)
ruby_key_down_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id)

	if keycode >= 30000 {
		// gamepad axis - requires gamepad parameter
		if argc < 2 || gamepad_id == mrb.NIL { return mrb.FALSE }
		gamepad := i32(mrb.integer(gamepad_id))
		axis := rl.GamepadAxis(keycode - 30000)
		axis_value := rl.GetGamepadAxisMovement(gamepad, axis)
		// consider axis "down" if absolute value > deadzone (0.1)
		return (axis_value > 0.1 || axis_value < -0.1) ? mrb.TRUE : mrb.FALSE
	} else if keycode >= 20000 {
		// gamepad button - requires gamepad parameter
		if argc < 2 || gamepad_id == mrb.NIL {
			return mrb.FALSE
		}
		gamepad := i32(mrb.integer(gamepad_id))
		button := rl.GamepadButton(keycode - 20000)
		return rl.IsGamepadButtonDown(gamepad, button) ? mrb.TRUE : mrb.FALSE
	} else if keycode >= 10000 {
		// mouse input - subtract offset to get MouseButton enum value
		mouse_button := rl.MouseButton(keycode - 10000)
		return rl.IsMouseButtonDown(mouse_button) ? mrb.TRUE : mrb.FALSE
	} else {
		// keyboard input
		is_down := rl.IsKeyDown(rl.KeyboardKey(keycode))
		return is_down ? mrb.TRUE : mrb.FALSE
	}
}

// RUBY FUNCTION: _key_pressed_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_pressed_impl", aspec=ARGS_ARG(1,1)
ruby_key_pressed_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id)

	// if we already saw pressed recorded this render frame,
	// we dont want to report it as pressed again
	if keycode in pressed_this_frame { return mrb.FALSE }

	pressed := false

	if keycode >= 30000 {
		// gamepad axis - no "pressed" state for axes, always false
		pressed = false
	} else if keycode >= 20000 {
		// gamepad button - requires gamepad parameter
		if argc < 2 || gamepad_id == mrb.NIL {
			pressed = false
		} else {
			gamepad := i32(mrb.integer(gamepad_id))
			button := rl.GamepadButton(keycode - 20000)
			pressed = rl.IsGamepadButtonPressed(gamepad, button)
		}
	} else if keycode >= 10000 {
		// mouse input - subtract offset to get MouseButton enum value
		mouse_button := rl.MouseButton(keycode - 10000)
		pressed = rl.IsMouseButtonPressed(mouse_button)
	} else {
		// keyboard input
		pressed = rl.IsKeyPressed(rl.KeyboardKey(keycode))
	}

	// record that we saw pressed this render frame
	if pressed { pressed_this_frame[keycode] = true }

	return pressed ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: _key_released_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_released_impl", aspec=ARGS_ARG(1,1)
ruby_key_released_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id)

	// if we already saw released recorded this render frame,
	// we dont want to report it as released again
	if keycode in released_this_frame { return mrb.FALSE }

	released := false

	if keycode >= 30000 {
		// gamepad axis - no "released" state for axes, always false
		released = false
	} else if keycode >= 20000 {
		// gamepad button - requires gamepad parameter
		if argc < 2 || gamepad_id == mrb.NIL {
			released = false
		} else {
			gamepad := i32(mrb.integer(gamepad_id))
			button := rl.GamepadButton(keycode - 20000)
			released = rl.IsGamepadButtonReleased(gamepad, button)
		}
	} else if keycode >= 10000 {
		// mouse input - subtract offset to get MouseButton enum value
		mouse_button := rl.MouseButton(keycode - 10000)
		released = rl.IsMouseButtonReleased(mouse_button)
	} else {
		// keyboard input
		released = rl.IsKeyReleased(rl.KeyboardKey(keycode))
	}

	// record that we saw released this render frame
	if released { released_this_frame[keycode] = true }

	return released ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: _keys_impl() -> [keys...]
// @engine_method: name="_keys_impl", aspec=ARGS_NONE
ruby_keys_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	keys_array := mrb.ary_new(g.mrb_state)

	if cached_keys_frame != g.frame_count {
		for i := 0; i < len(cached_keys); i += 1 {
			key := rl.GetKeyPressed()
			if key == .KEY_NULL {
				cached_keys[i] = .KEY_NULL
				break
			}
			cached_keys[i] = key
		}
		cached_keys_frame = g.frame_count
	}

	for key in cached_keys {
		if key == .KEY_NULL { break }
		mrb.ary_push(g.mrb_state, keys_array, mrb.boxing_int_value(g.mrb_state, i32(key)))
	}

	return keys_array
}


// RUBY FUNCTION: mouse(layer = :world) -> Vector2
// @engine_method: name="mouse", aspec=ARGS_OPT(1)
ruby_mouse :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	// extract optional layer parameter
	layer_sym: mrb.Sym
	argc := mrb.get_args(state, "|n", &layer_sym)

	// return cached result if already calculated this frame
	if cached_mouse_frame == g.frame_count {
		if argc == 0 || layer_sym == mrb.intern_cstr(state, "world") {
			return create_vector2(cached_mouse_world)
		} else if layer_sym == mrb.intern_cstr(state, "ui") {
			return create_vector2(cached_mouse_ui)
		}
		return mrb.NIL
	}

	// calculate mouse position once per frame
	screen_mouse_pos := rl.GetMousePosition()

	// convert from screen coordinates to game texture coordinates
	mouse_pos: rl.Vector2
	when ODIN_OS != .JS {
		// native builds: handle scaling and centering
		screen_w, screen_h: f32
		if rl.IsWindowFullscreen() {
			monitor := rl.GetCurrentMonitor()
			screen_w = f32(rl.GetMonitorWidth(monitor))
			screen_h = f32(rl.GetMonitorHeight(monitor))
		} else {
			screen_w = f32(rl.GetScreenWidth())
			screen_h = f32(rl.GetScreenHeight())
		}

		game_w := g.resolution.x
		game_h := g.resolution.y

		// calculate scale factor (same logic as main.odin)
		scale_x := screen_w / game_w
		scale_y := screen_h / game_h
		scale := min(scale_x, scale_y)

		// calculate centered position offset
		scaled_w := game_w * scale
		scaled_h := game_h * scale
		offset_x := (screen_w - scaled_w) / 2
		offset_y := (screen_h - scaled_h) / 2

		// convert screen position to texture coordinates
		texture_x := (screen_mouse_pos.x - offset_x) / scale
		texture_y := (screen_mouse_pos.y - offset_y) / scale
		mouse_pos = {texture_x, texture_y}
	} else {
		// web builds: simple stretch scaling
		texture_x := screen_mouse_pos.x * g.resolution.x / f32(rl.GetScreenWidth())
		texture_y := screen_mouse_pos.y * g.resolution.y / f32(rl.GetScreenHeight())
		mouse_pos = {texture_x, texture_y}
	}

	// cache both world and UI positions
	cached_mouse_world = rl.GetScreenToWorld2D(mouse_pos, g.camera)
	cached_mouse_ui = rl.GetScreenToWorld2D(mouse_pos, {zoom = 1})
	cached_mouse_frame = g.frame_count

	// return appropriate cached result
	if argc == 0 || layer_sym == mrb.intern_cstr(state, "world") {
		return create_vector2(cached_mouse_world)
	} else if layer_sym == mrb.intern_cstr(state, "ui") {
		return create_vector2(cached_mouse_ui)
	}

	return mrb.NIL
}

// RUBY FUNCTION: _gamepad_available_impl(id) -> bool
// @engine_method: name="gamepad?", aspec=ARGS_REQ(1)
ruby_gamepad_available_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	gamepad_id_val: mrb.Value
	mrb.get_args(state, "o", &gamepad_id_val)

	if gamepad_id_val == mrb.NIL { return mrb.raise_error(state, "ArgumentError", "Specify gamepad ID") }
	gamepad_id := i32(mrb.integer(gamepad_id_val))

	return rl.IsGamepadAvailable(gamepad_id) ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: _get_gamepad_axis_value(xcode, ycode, gamepad_id) -> float
// @engine_method: name="_get_gamepad_axis_value", aspec=ARGS_REQ(3)
ruby_get_gamepad_axis_value :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	xcode_val, ycode_val, gamepad_val: mrb.Value
	mrb.get_args(state, "ooo", &xcode_val, &ycode_val, &gamepad_val)

	xcode := i32(mrb.integer(xcode_val))
	ycode := i32(mrb.integer(ycode_val))
	gamepad_id := i32(mrb.integer(gamepad_val))

	if xcode >= 30000 && ycode <= 30003 {
		x_val := rl.GetGamepadAxisMovement(gamepad_id, rl.GamepadAxis(xcode - 30000))
		y_val := rl.GetGamepadAxisMovement(gamepad_id, rl.GamepadAxis(ycode - 30000))
		return create_vector2(vector2_normalized({x_val, y_val}))
	}

	return create_vector2({0, 0})
}

cleanup_input :: proc() {
	delete(pressed_this_frame)
	delete(released_this_frame)
}
