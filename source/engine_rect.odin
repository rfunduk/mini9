package engine

import mrb "lib:mruby"
import rl "vendor:raylib"

ruby_rect_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_rect :: proc(r: rl.Rectangle) -> mrb.Value {
	rect_ptr := mrb.alloc(g.mrb_state, r)

	rect_class := mrb.class_get(g.mrb_state, "Rect")
	ruby_obj := mrb.obj_new(g.mrb_state, rect_class, 0, nil)

	mrb.data_init(ruby_obj, rect_ptr, NATIVE_TO_MRUBY_TYPE[rl.Rectangle])

	return ruby_obj
}

// RUBY FUNCTION: rect(*args) -> rect function that handles both signatures
// supports rect(size_v2) or rect(pos_v2, size_v2) or rect(x, y, w, h)
// @engine_method: name="rect", arity=-1
ruby_rect :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)

	args := (cast([^]mrb.Value)argv)[:argc]

	switch argc {
	case 1:
		// rect(size) - size is Vector2
		size_ptr := extract_native(rl.Vector2, args[0])
		if size_ptr == nil {
			return mrb.raise_error(state, "ArgumentError", "rect(size): argument must be a Vector2")
		}
		size := size_ptr^
		return create_rect({0, 0, size.x, size.y})

	case 2:
		// rect(pos, size) - both Vector2
		pos_ptr := extract_native(rl.Vector2, args[0])
		size_ptr := extract_native(rl.Vector2, args[1])
		if pos_ptr == nil {
			return mrb.raise_error(
				state,
				"ArgumentError",
				"rect(pos, size): first argument must be a Vector2",
			)
		}
		if size_ptr == nil {
			return mrb.raise_error(
				state,
				"ArgumentError",
				"rect(pos, size): second argument must be a Vector2",
			)
		}
		pos := pos_ptr^
		size := size_ptr^
		return create_rect({pos.x, pos.y, size.x, size.y})

	case 4:
		// rect(x, y, w, h) - four floats
		x := f32(mrb.to_f64(args[0]))
		y := f32(mrb.to_f64(args[1]))
		w := f32(mrb.to_f64(args[2]))
		h := f32(mrb.to_f64(args[3]))
		return create_rect({x, y, w, h})

	case:
		return mrb.raise_error(
			state,
			"ArgumentError",
			"rect(): wrong number of arguments (given %d, expected 1, 2, or 4)",
			argc,
		)
	}
}

ruby_rect_get_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	return mrb.word_boxing_float_value(state, r == nil ? 0 : f64(r.x))
}

ruby_rect_get_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	return mrb.word_boxing_float_value(state, r == nil ? 0 : f64(r.y))
}

ruby_rect_get_w :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	return mrb.word_boxing_float_value(state, r == nil ? 0 : f64(r.width))
}

ruby_rect_get_h :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	return mrb.word_boxing_float_value(state, r == nil ? 0 : f64(r.height))
}

ruby_rect_set_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new: f64
	mrb.get_args(state, "f", &new)

	old_r := extract_native(rl.Rectangle, self)
	if old_r == nil { return mrb.NIL }

	new_ptr := mrb.alloc(g.mrb_state, rl.Rectangle{f32(new), old_r.y, old_r.width, old_r.height})
	mrb.data_init(self, new_ptr, NATIVE_TO_MRUBY_TYPE[rl.Rectangle])

	return mrb.word_boxing_float_value(state, new)
}

ruby_rect_set_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new: f64
	mrb.get_args(state, "f", &new)

	old_r := extract_native(rl.Rectangle, self)
	if old_r == nil { return mrb.NIL }

	new_ptr := mrb.alloc(g.mrb_state, rl.Rectangle{old_r.x, f32(new), old_r.width, old_r.height})
	mrb.data_init(self, new_ptr, NATIVE_TO_MRUBY_TYPE[rl.Rectangle])

	return mrb.word_boxing_float_value(state, new)
}

ruby_rect_set_w :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new: f64
	mrb.get_args(state, "f", &new)

	old_r := extract_native(rl.Rectangle, self)
	if old_r == nil { return mrb.NIL }

	new_ptr := mrb.alloc(g.mrb_state, rl.Rectangle{old_r.x, old_r.y, f32(new), old_r.height})
	mrb.data_init(self, new_ptr, NATIVE_TO_MRUBY_TYPE[rl.Rectangle])

	return mrb.word_boxing_float_value(state, new)
}

ruby_rect_set_h :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new: f64
	mrb.get_args(state, "f", &new)

	old_r := extract_native(rl.Rectangle, self)
	if old_r == nil { return mrb.NIL }

	new_ptr := mrb.alloc(g.mrb_state, rl.Rectangle{old_r.x, old_r.y, old_r.width, f32(new)})
	mrb.data_init(self, new_ptr, NATIVE_TO_MRUBY_TYPE[rl.Rectangle])

	return mrb.word_boxing_float_value(state, new)
}

ruby_inflate_rect :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	amount_or_t, r, b, l: f64
	argc := mrb.get_args(state, "f|fff", &amount_or_t, &r, &b, &l)

	rect := extract_native(rl.Rectangle, self)
	if rect == nil { return mrb.NIL }

	if argc == 1 {
		return create_rect(inflate_rect(rect^, f32(amount_or_t)))
	} else {
		return create_rect(inflate_rect(rect^, [4]f32{f32(amount_or_t), f32(r), f32(b), f32(l)}))
	}
}

inflate_rect :: proc {
	inflate_rect_trbl,
	inflate_rect_uniform,
}

inflate_rect_trbl :: proc(rect: rl.Rectangle, trbl: [4]f32) -> rl.Rectangle {
	rect := rect
	rect.x -= trbl[3]
	rect.y -= trbl[0]
	rect.width += trbl[3] + trbl[1]
	rect.height += trbl[0] + trbl[2]
	return rect
}

inflate_rect_uniform :: proc(rect: rl.Rectangle, amount: f32) -> rl.Rectangle {
	rect := rect
	rect.x -= amount
	rect.y -= amount
	rect.width += amount * 2
	rect.height += amount * 2
	return rect
}

setup_rect :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Rect")

	mrb.define_method(g.mrb_state, c, "new", cast(rawptr)ruby_rect, -1)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_rect_get_x, 0)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_rect_get_y, 0)
	mrb.define_method(g.mrb_state, c, "w", cast(rawptr)ruby_rect_get_w, 0)
	mrb.define_method(g.mrb_state, c, "h", cast(rawptr)ruby_rect_get_h, 0)
	mrb.define_method(g.mrb_state, c, "x=", cast(rawptr)ruby_rect_set_x, 1)
	mrb.define_method(g.mrb_state, c, "y=", cast(rawptr)ruby_rect_set_y, 1)
	mrb.define_method(g.mrb_state, c, "w=", cast(rawptr)ruby_rect_set_w, 1)
	mrb.define_method(g.mrb_state, c, "h=", cast(rawptr)ruby_rect_set_h, 1)
}
