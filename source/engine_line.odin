package engine

import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "lib:raylib"

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

// RUBY FUNCTION: line(to) — from v2(0) to `to`. Or line(a, b) — explicit endpoints.
// @engine_method: name="line", aspec=ARGS_ANY
ruby_line :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)
	args := (cast([^]mrb.Value)argv)[:argc]

	switch argc {
	case 1:
		bp := extract_native(rl.Vector2, args[0])
		if bp == nil {
			return mrb.raise_error(state, "ArgumentError", "line(to): argument must be Vector2")
		}
		return create_line({{0, 0}, bp^})
	case 2:
		ap := extract_native(rl.Vector2, args[0])
		bp := extract_native(rl.Vector2, args[1])
		if ap == nil || bp == nil {
			return mrb.raise_error(state, "ArgumentError", "line(a, b): both args must be Vector2")
		}
		return create_line({ap^, bp^})
	case:
		return mrb.raise_error(
			state,
			"ArgumentError",
			"line(): wrong number of arguments (given %d, expected 1 or 2)",
			argc,
		)
	}
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

ruby_line_add :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	l := extract_native(Line, self)
	v := extract_or_raise(rl.Vector2, other, "Line#+ expects a Vector2")
	return create_line({l.a + v^, l.b + v^})
}

ruby_line_subtract :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	l := extract_native(Line, self)
	v := extract_or_raise(rl.Vector2, other, "Line#- expects a Vector2")
	return create_line({l.a - v^, l.b - v^})
}

setup_line :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Line")
	mrb.define_method(g.mrb_state, c, "+", cast(rawptr)ruby_line_add, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "-", cast(rawptr)ruby_line_subtract, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "a", cast(rawptr)ruby_line_get_a, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "b", cast(rawptr)ruby_line_get_b, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "length", cast(rawptr)ruby_line_length, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "midpoint", cast(rawptr)ruby_line_midpoint, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_line_draw, mrb.ARGS_OPT(1))

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
