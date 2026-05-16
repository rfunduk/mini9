package engine

import "core:math"
import lin "core:math/linalg"
import "core:math/rand"
import mrb "lib:mruby"
import rl "lib:raylib"

Circ :: struct {
	center: rl.Vector2,
	r:      f32,
}

ruby_circ_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_circ :: proc(c: Circ) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, c)
	class := mrb.class_get(g.mrb_state, "Circ")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Circ])
	return ruby_obj
}

// RUBY FUNCTION: circ(*args) -> circle function that handles several signatures
// @engine_method: name="circ", aspec=ARGS_ANY
ruby_circ :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)
	args := (cast([^]mrb.Value)argv)[:argc]

	switch argc {
	case 1:
		return create_circ({{0, 0}, f32(mrb.to_f64(args[0]))})
	case 2:
		center := extract_native(rl.Vector2, args[0])
		if center == nil {
			return mrb.raise_error(state, "ArgumentError", "circ(center, radius): center must be Vector2")
		}
		return create_circ({center^, f32(mrb.to_f64(args[1]))})
	case 3:
		return create_circ({{f32(mrb.to_f64(args[0])), f32(mrb.to_f64(args[1]))}, f32(mrb.to_f64(args[2]))})
	case:
		return mrb.raise_error(
			state,
			"ArgumentError",
			"circ(): wrong number of arguments (given %d, expected 1, 2, or 3)",
			argc,
		)
	}
}

ruby_circ_get_center :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Circ, self)
	if c == nil { return create_vector2({0, 0}) }
	return create_vector2(c.center)
}

ruby_circ_get_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Circ, self)
	return mrb.word_boxing_float_value(state, c == nil ? 0 : f64(c.center.x))
}

ruby_circ_get_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Circ, self)
	return mrb.word_boxing_float_value(state, c == nil ? 0 : f64(c.center.y))
}

ruby_circ_get_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Circ, self)
	return mrb.word_boxing_float_value(state, c == nil ? 0 : f64(c.r))
}

ruby_circ_set_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	c := extract_native(Circ, self)
	if c != nil { c.center.x = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_circ_set_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	c := extract_native(Circ, self)
	if c != nil { c.center.y = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_circ_set_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	c := extract_native(Circ, self)
	if c != nil { c.r = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_circ_contains :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p_val: mrb.Value
	mrb.get_args(state, "o", &p_val)
	c := extract_native(Circ, self)
	p := extract_native(rl.Vector2, p_val)
	if c == nil || p == nil { return mrb.FALSE }
	dx := p.x - c.center.x
	dy := p.y - c.center.y
	return (dx * dx + dy * dy <= c.r * c.r) ? mrb.TRUE : mrb.FALSE
}

ruby_circ_distance :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p_val: mrb.Value
	mrb.get_args(state, "o", &p_val)
	c := extract_native(Circ, self)
	p := extract_native(rl.Vector2, p_val)
	if c == nil || p == nil { return mrb.word_boxing_float_value(state, 0) }
	dx := p.x - c.center.x
	dy := p.y - c.center.y
	return mrb.word_boxing_float_value(state, f64(math.sqrt(dx * dx + dy * dy)))
}

ruby_circ_overlaps :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	c := extract_native(Circ, self)
	if c == nil { return mrb.FALSE }

	if is_native(Circ, other) {
		o := extract_native(Circ, other)
		dx := o.center.x - c.center.x
		dy := o.center.y - c.center.y
		sum := c.r + o.r
		return (dx * dx + dy * dy <= sum * sum) ? mrb.TRUE : mrb.FALSE
	}
	if is_native(rl.Rectangle, other) {
		r := extract_native(rl.Rectangle, other)
		closest_x := clamp(c.center.x, r.x, r.x + r.width)
		closest_y := clamp(c.center.y, r.y, r.y + r.height)
		dx := c.center.x - closest_x
		dy := c.center.y - closest_y
		return (dx * dx + dy * dy <= c.r * c.r) ? mrb.TRUE : mrb.FALSE
	}
	return mrb.raise_error(state, "TypeError", "Circ#overlaps? expects Circ or Rect")
}

ruby_circ_sample_point :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Circ, self)
	if c == nil { return create_vector2({0, 0}) }
	// uniform sampling via sqrt(rand) for radius (area-correct)
	theta := rand.float32() * 2 * math.PI
	radius := math.sqrt(rand.float32()) * c.r
	return create_vector2({c.center.x + radius * math.cos(theta), c.center.y + radius * math.sin(theta)})
}

ruby_circ_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	c := extract_native(Circ, self)
	if c == nil { return mrb.NIL }

	offset := _parse_offset_kwarg(state, kwargs)
	draw_circle(
		pos = c.center + offset,
		radius = c.r,
		color = _parse_color_kwarg(state, kwargs),
		thickness = _parse_f32_kwarg(state, kwargs, sym.thickness, 1),
		filled = _parse_bool_kwarg(state, kwargs, sym.filled),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
}

ruby_circ_add :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	c := extract_native(Circ, self)
	v := extract_native(rl.Vector2, other)
	if c == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Circ#+ expects a Vector2") }
	return create_circ({c.center + v^, c.r})
}

ruby_circ_subtract :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	c := extract_native(Circ, self)
	v := extract_native(rl.Vector2, other)
	if c == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Circ#- expects a Vector2") }
	return create_circ({c.center - v^, c.r})
}

setup_circ :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Circ")
	mrb.define_method(g.mrb_state, c, "+", cast(rawptr)ruby_circ_add, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "-", cast(rawptr)ruby_circ_subtract, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "center", cast(rawptr)ruby_circ_get_center, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_circ_get_x, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_circ_get_y, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "r", cast(rawptr)ruby_circ_get_r, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "radius", cast(rawptr)ruby_circ_get_r, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x=", cast(rawptr)ruby_circ_set_x, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "y=", cast(rawptr)ruby_circ_set_y, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "r=", cast(rawptr)ruby_circ_set_r, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "radius=", cast(rawptr)ruby_circ_set_r, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "contains?", cast(rawptr)ruby_circ_contains, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "distance", cast(rawptr)ruby_circ_distance, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "overlaps?", cast(rawptr)ruby_circ_overlaps, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "sample_point", cast(rawptr)ruby_circ_sample_point, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_circ_draw, mrb.ARGS_OPT(1))

}

draw_circle :: proc(
	pos: rl.Vector2,
	radius: f32,
	color: rl.Color = {255, 255, 255, 255},
	thickness: f32 = 1,
	filled: bool = false,
	clip: Maybe(rl.Rectangle) = nil,
) {
	p := lin.floor(pos)

	did_clip := _clip(clip, p)

	if filled {
		// DrawCircleSector uses the shapes texture (batches with atlas);
		// DrawCircleV bypasses it. 36 segments matches DrawCircleV quality.
		rl.DrawCircleSector(p, radius, 0, 360, 36, color)
	} else {
		// DrawRing (filled annulus) instead of DrawCircleLinesV so the
		// outline batches with other shape draws — line primitives force a
		// batch flush -> extra draw call. thickness controls ring width.
		inner := max(radius - thickness, 0)
		rl.DrawRing(p, inner, radius, 0, 360, 36, color)
	}

	if did_clip { rl.EndScissorMode() }
}
