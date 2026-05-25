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

// Per-key edge queue. Wall-frame sweep appends PRESS/RELEASE events into
// `bits` (bit 0 = oldest, 0 = PRESS, 1 = RELEASE). Each scaled tick pops
// the front via advance_input_edges() into `input_current_edges`. Caps at
// 32 events per key; overflow drops the newest. Keys are mini9 keycodes
// (raylib KeyboardKey i32, mouse +10000, gamepad button +20000+pad*100).
Edge_Kind :: enum u8 {
	NONE,
	PRESS,
	RELEASE,
}

Key_Edges :: struct {
	bits:  u32,
	count: u8,
}

input_edge_queue: map[i32]Key_Edges
input_current_edges: map[i32]Edge_Kind

@(private = "file")
append_edge :: proc(keycode: i32, is_release: bool) {
	e := input_edge_queue[keycode]
	if e.count >= 32 { return }
	if is_release { e.bits |= (u32(1) << e.count) }
	e.count += 1
	input_edge_queue[keycode] = e
}

advance_input_edges :: proc() {
	clear(&input_current_edges)
	for k, &e in input_edge_queue {
		if e.count == 0 { continue }
		is_release := (e.bits & 1) == 1
		input_current_edges[k] = is_release ? .RELEASE : .PRESS
		e.bits >>= 1
		e.count -= 1
	}
}

sweep_input_edges :: proc() {
	for k in rl.KeyboardKey {
		if k == .KEY_NULL { continue }
		code := i32(k)
		if rl.IsKeyPressed(k) { append_edge(code, false) }
		if rl.IsKeyReleased(k) { append_edge(code, true) }
	}
	for b in rl.MouseButton {
		code := i32(b) + 10000
		if rl.IsMouseButtonPressed(b) { append_edge(code, false) }
		if rl.IsMouseButtonReleased(b) { append_edge(code, true) }
	}
	for pad in i32(0) ..< 4 {
		if !rl.IsGamepadAvailable(pad) { continue }
		for btn in rl.GamepadButton {
			if btn == .UNKNOWN { continue }
			code := i32(btn) + 20000 + pad * 100
			if rl.IsGamepadButtonPressed(pad, btn) { append_edge(code, false) }
			if rl.IsGamepadButtonReleased(pad, btn) { append_edge(code, true) }
		}
	}
}

// Map a Ruby-facing keycode + gamepad id into the i32 queue key used by
// input_edge_queue / input_current_edges. Gamepad button codes embed the
// pad id so different pads sharing the same button get distinct queues.
@(private = "file")
queue_key :: proc(keycode: i32, gamepad_id: i32) -> i32 {
	if keycode >= 20000 && keycode < 30000 { return keycode + gamepad_id * 100 }
	return keycode
}

// RUBY FUNCTION: _key_down_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_down_impl", aspec=ARGS_ARG(1,1)
ruby_key_down_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id_val: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id_val)

	if keycode >= 30000 {
		if argc < 2 || gamepad_id_val == mrb.NIL { return mrb.FALSE }
		gamepad := i32(mrb.integer(gamepad_id_val))
		axis := rl.GamepadAxis(keycode - 30000)
		axis_value := rl.GetGamepadAxisMovement(gamepad, axis)
		return (axis_value > 0.1 || axis_value < -0.1) ? mrb.TRUE : mrb.FALSE
	}

	gamepad: i32 = 0
	raw_down := false
	if keycode >= 20000 {
		if argc < 2 || gamepad_id_val == mrb.NIL { return mrb.FALSE }
		gamepad = i32(mrb.integer(gamepad_id_val))
		raw_down = rl.IsGamepadButtonDown(gamepad, rl.GamepadButton(keycode - 20000))
	} else if keycode >= 10000 {
		raw_down = rl.IsMouseButtonDown(rl.MouseButton(keycode - 10000))
	} else {
		raw_down = rl.IsKeyDown(rl.KeyboardKey(keycode))
	}

	if raw_down { return mrb.TRUE }
	if input_current_edges[queue_key(keycode, gamepad)] == .PRESS { return mrb.TRUE }
	return mrb.FALSE
}

// RUBY FUNCTION: _key_pressed_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_pressed_impl", aspec=ARGS_ARG(1,1)
ruby_key_pressed_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id_val: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id_val)

	if keycode >= 30000 { return mrb.FALSE }

	gamepad: i32 = 0
	if keycode >= 20000 {
		if argc < 2 || gamepad_id_val == mrb.NIL { return mrb.FALSE }
		gamepad = i32(mrb.integer(gamepad_id_val))
	}

	return input_current_edges[queue_key(keycode, gamepad)] == .PRESS ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: _key_released_impl(keycode, gamepad=nil) -> bool
// @engine_method: name="_key_released_impl", aspec=ARGS_ARG(1,1)
ruby_key_released_impl :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	keycode: i32
	gamepad_id_val: mrb.Value
	argc := mrb.get_args(state, "i|o", &keycode, &gamepad_id_val)

	if keycode >= 30000 { return mrb.FALSE }

	gamepad: i32 = 0
	if keycode >= 20000 {
		if argc < 2 || gamepad_id_val == mrb.NIL { return mrb.FALSE }
		gamepad = i32(mrb.integer(gamepad_id_val))
	}

	return input_current_edges[queue_key(keycode, gamepad)] == .RELEASE ? mrb.TRUE : mrb.FALSE
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
	delete(input_edge_queue)
	delete(input_current_edges)
}
