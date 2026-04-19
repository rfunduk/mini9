package engine

import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

Oval :: struct {
	pos:  rl.Vector2, // center
	size: rl.Vector2, // half-axes (width/height radii)
}

ruby_oval_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_oval :: proc(o: Oval) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, o)
	class := mrb.class_get(g.mrb_state, "Oval")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Oval])
	return ruby_obj
}

// RUBY FUNCTION: oval(pos, size) — pos = center, size = v2(w_radius, h_radius).
// @engine_method: name="oval", arity=2
ruby_oval :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val, size_val: mrb.Value
	mrb.get_args(state, "oo", &pos_val, &size_val)

	pos := extract_native(rl.Vector2, pos_val)
	size := extract_native(rl.Vector2, size_val)
	if pos == nil || size == nil {
		return mrb.raise_error(state, "ArgumentError", "oval(pos, size): both args must be Vector2")
	}

	return create_oval({pos^, size^})
}

ruby_oval_get_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	if o == nil { return create_vector2({}) }
	return create_vector2(o.pos)
}

ruby_oval_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	if o == nil { return create_vector2({}) }
	return create_vector2(o.size)
}

ruby_oval_get_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	return mrb.word_boxing_float_value(state, o == nil ? 0 : f64(o.pos.x))
}

ruby_oval_get_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	return mrb.word_boxing_float_value(state, o == nil ? 0 : f64(o.pos.y))
}

ruby_oval_get_w :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	return mrb.word_boxing_float_value(state, o == nil ? 0 : f64(o.size.x))
}

ruby_oval_get_h :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	o := extract_native(Oval, self)
	return mrb.word_boxing_float_value(state, o == nil ? 0 : f64(o.size.y))
}

ruby_oval_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	o := extract_native(Oval, self)
	if o == nil { return mrb.NIL }

	offset := _parse_offset_kwarg(state, kwargs)
	draw_oval(
		pos = {o.pos.x + offset.x, o.pos.y + offset.y},
		size = o.size,
		color = _parse_color_kwarg(state, kwargs),
		filled = _parse_bool_kwarg(state, kwargs, sym.filled),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
}

draw_oval :: proc(
	pos: rl.Vector2,
	size: rl.Vector2,
	color: rl.Color = {255, 255, 255, 255},
	filled: bool = false,
	clip: Maybe(rl.Rectangle) = nil,
) {
	p := lin.floor(pos)
	s := lin.floor(size)

	did_clip := _clip(clip, p)

	if filled {
		rl.DrawEllipse(i32(p.x), i32(p.y), s.x, s.y, color)
	} else {
		rl.DrawEllipseLines(i32(p.x), i32(p.y), s.x, s.y, color)
	}

	if did_clip { rl.EndScissorMode() }
}

setup_oval :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Oval")
	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_oval_get_pos, 0)
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_oval_get_size, 0)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_oval_get_x, 0)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_oval_get_y, 0)
	mrb.define_method(g.mrb_state, c, "w", cast(rawptr)ruby_oval_get_w, 0)
	mrb.define_method(g.mrb_state, c, "h", cast(rawptr)ruby_oval_get_h, 0)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_oval_draw, -1)
}
