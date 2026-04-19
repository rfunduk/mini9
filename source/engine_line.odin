package engine

import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

Line :: struct {
	a: rl.Vector2,
	b: rl.Vector2,
}

ruby_line_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_line :: proc(l: Line) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, l)
	class := mrb.class_get(g.mrb_state, "Line")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Line])
	return ruby_obj
}

// RUBY FUNCTION: line(a, b) — a and b are Vector2.
// @engine_method: name="line", arity=2
ruby_line :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	a_val, b_val: mrb.Value
	mrb.get_args(state, "oo", &a_val, &b_val)

	ap := extract_native(rl.Vector2, a_val)
	bp := extract_native(rl.Vector2, b_val)
	if ap == nil || bp == nil {
		return mrb.raise_error(state, "ArgumentError", "line(a, b): both args must be Vector2")
	}

	return create_line({ap^, bp^})
}

ruby_line_get_a :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	l := extract_native(Line, self)
	if l == nil { return create_vector2({}) }
	return create_vector2(l.a)
}

ruby_line_get_b :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	l := extract_native(Line, self)
	if l == nil { return create_vector2({}) }
	return create_vector2(l.b)
}

ruby_line_length :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	l := extract_native(Line, self)
	if l == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, f64(lin.length(l.b - l.a)))
}

ruby_line_midpoint :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	l := extract_native(Line, self)
	if l == nil { return create_vector2({}) }
	return create_vector2({(l.a.x + l.b.x) * 0.5, (l.a.y + l.b.y) * 0.5})
}

ruby_line_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	l := extract_native(Line, self)
	if l == nil { return mrb.NIL }

	offset := _parse_offset_kwarg(state, kwargs)
	draw_line(
		from = {l.a.x + offset.x, l.a.y + offset.y},
		to = {l.b.x + offset.x, l.b.y + offset.y},
		color = _parse_color_kwarg(state, kwargs),
		thickness = _parse_f32_kwarg(state, kwargs, sym.thickness, 1),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
}

setup_line :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Line")
	mrb.define_method(g.mrb_state, c, "a", cast(rawptr)ruby_line_get_a, 0)
	mrb.define_method(g.mrb_state, c, "b", cast(rawptr)ruby_line_get_b, 0)
	mrb.define_method(g.mrb_state, c, "length", cast(rawptr)ruby_line_length, 0)
	mrb.define_method(g.mrb_state, c, "midpoint", cast(rawptr)ruby_line_midpoint, 0)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_line_draw, -1)
}

draw_line :: proc(
	from: rl.Vector2,
	to: rl.Vector2,
	color: rl.Color = {255, 255, 255, 255},
	thickness: f32 = 1,
	clip: Maybe(rl.Rectangle) = nil,
) {
	f := lin.floor(from)
	t := lin.floor(to)

	did_clip := _clip(clip, f)

	// rotated stretched white-texel quad — batches with the atlas since
	// DrawLineEx uses RL_LINES mode which forces a batch flush.
	delta := t - f
	length := lin.length(delta)
	if length > 0 {
		angle_deg := math.atan2(delta.y, delta.x) * 180.0 / math.PI
		rl.DrawTexturePro(
			atlas_texture,
			atlas_white_uv,
			{f.x, f.y, length, thickness},
			{0, thickness / 2},
			angle_deg,
			color,
		)
	}

	if did_clip { rl.EndScissorMode() }
}
