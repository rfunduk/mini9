package engine

import lin "core:math/linalg"
import "core:math/rand"
import mrb "lib:mruby"
import rl "lib:raylib"

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

// RUBY FUNCTION: rect(*args) -> rect function that handles several signatures
// @engine_method: name="rect", aspec=ARGS_ANY
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

ruby_rect_get_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	if r == nil { return create_vector2({}) }
	return create_vector2({r.x, r.y})
}

ruby_rect_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	if r == nil { return create_vector2({}) }
	return create_vector2({r.width, r.height})
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

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)
	args := (cast([^]mrb.Value)argv)[:argc]

	rect := extract_native(rl.Rectangle, self)
	if rect == nil { return mrb.NIL }

	switch argc {
	case 1:
		v := args[0]
		if is_native(rl.Vector2, v) {
			vec := extract_native(rl.Vector2, v)
			return create_rect(inflate_rect(rect^, [4]f32{vec.y, vec.x, vec.y, vec.x}))
		}
		if mrb.integer_p(v) || mrb.float_p(v) {
			return create_rect(inflate_rect(rect^, f32(mrb.to_f64(v))))
		}
		return mrb.raise_error(state, "ArgumentError", "inflate: arg must be Numeric or Vector2")
	case 4:
		return create_rect(
			inflate_rect(
				rect^,
				[4]f32 {
					f32(mrb.to_f64(args[0])),
					f32(mrb.to_f64(args[1])),
					f32(mrb.to_f64(args[2])),
					f32(mrb.to_f64(args[3])),
				},
			),
		)
	case:
		return mrb.raise_error(
			state,
			"ArgumentError",
			"inflate: expected 1 (Numeric or Vector2) or 4 (t,r,b,l) args",
		)
	}
}

ruby_rect_contains :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p_val: mrb.Value
	mrb.get_args(state, "o", &p_val)
	r := extract_native(rl.Rectangle, self)
	p := extract_native(rl.Vector2, p_val)
	if r == nil || p == nil { return mrb.FALSE }
	if p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height {
		return mrb.TRUE
	}
	return mrb.FALSE
}

ruby_rect_sample_point :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r := extract_native(rl.Rectangle, self)
	if r == nil { return create_vector2({}) }
	return create_vector2({r.x + rand.float32() * r.width, r.y + rand.float32() * r.height})
}

ruby_rect_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	r := extract_native(rl.Rectangle, self)
	if r == nil { return mrb.NIL }

	offset := _parse_offset_kwarg(state, kwargs)
	draw_rectangle(
		pos = {r.x + offset.x, r.y + offset.y},
		size = {r.width, r.height},
		color = _parse_color_kwarg(state, kwargs),
		thickness = _parse_f32_kwarg(state, kwargs, sym.thickness, 1),
		rounded = _parse_f32_kwarg(state, kwargs, sym.rounded, 0) / 100.0,
		filled = _parse_bool_kwarg(state, kwargs, sym.filled),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
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

	mrb.define_method(g.mrb_state, c, "new", cast(rawptr)ruby_rect, mrb.ARGS_ANY)
	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_rect_get_pos, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_rect_get_size, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_rect_get_x, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_rect_get_y, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "w", cast(rawptr)ruby_rect_get_w, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "h", cast(rawptr)ruby_rect_get_h, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x=", cast(rawptr)ruby_rect_set_x, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "y=", cast(rawptr)ruby_rect_set_y, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "w=", cast(rawptr)ruby_rect_set_w, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "h=", cast(rawptr)ruby_rect_set_h, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "sample_point", cast(rawptr)ruby_rect_sample_point, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "inflate", cast(rawptr)ruby_inflate_rect, mrb.ARGS_ANY)
	mrb.define_method(g.mrb_state, c, "contains?", cast(rawptr)ruby_rect_contains, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_rect_draw, mrb.ARGS_OPT(1))

}

draw_rectangle :: proc(
	pos: rl.Vector2,
	size: rl.Vector2,
	color: rl.Color = {255, 255, 255, 255},
	thickness: f32 = 1,
	rounded: f32 = 0, // 0..1 (fraction of shorter edge)
	filled: bool = false,
	clip: Maybe(rl.Rectangle) = nil,
) {
	p := lin.floor(pos)
	s := lin.floor(size)

	did_clip := _clip(clip, p)

	if filled {
		if rounded > 0 {
			rl.DrawRectangleRounded({p.x, p.y, s.x, s.y}, rounded, 10, color)
		} else {
			// DrawRectanglePro uses the shapes texture (batches with atlas);
			// DrawRectangleV bypasses it.
			rl.DrawRectanglePro({p.x, p.y, s.x, s.y}, {0, 0}, 0, color)
		}
	} else {
		if rounded > 0 {
			rl.DrawRectangleRoundedLinesEx(
				{p.x, p.y, s.x, s.y},
				rounded,
				i32(max(s.x, s.y) / 2),
				thickness,
				color,
			)
		} else {
			rl.DrawRectangleLinesEx({p.x, p.y, s.x, s.y}, thickness, color)
		}
	}

	if did_clip { rl.EndScissorMode() }
}
