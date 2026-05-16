package engine

import "core:math"
import lin "core:math/linalg"
import "core:math/rand"
import mrb "lib:mruby"
import rl "lib:raylib"

// Drawing-only primitive: circular wedge. Angles are radians, CCW from +x
// (same convention as Vector2#angle). No physics — an arc collider is
// nonsensical; use circ/rect/poly for collision.
Arc :: struct {
	cx:    f32,
	cy:    f32,
	r:     f32,
	start: f32, // radians
	sweep: f32, // radians, signed
}

ruby_arc_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_arc :: proc(a: Arc) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, a)
	class := mrb.class_get(g.mrb_state, "Arc")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Arc])
	return ruby_obj
}

// RUBY FUNCTION: arc(*args) -> arc function that handles several signatures
// @engine_method: name="arc", aspec=ARGS_ANY
ruby_arc :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)
	args := (cast([^]mrb.Value)argv)[:argc]

	switch argc {
	case 3:
		return create_arc(
			{0, 0, f32(mrb.to_f64(args[0])), f32(mrb.to_f64(args[1])), f32(mrb.to_f64(args[2]))},
		)
	case 4:
		center := extract_native(rl.Vector2, args[0])
		if center == nil {
			return mrb.raise_error(
				state,
				"ArgumentError",
				"arc(center, radius, start, sweep): center must be Vector2",
			)
		}
		return create_arc(
			{
				center.x,
				center.y,
				f32(mrb.to_f64(args[1])),
				f32(mrb.to_f64(args[2])),
				f32(mrb.to_f64(args[3])),
			},
		)
	case 5:
		return create_arc(
			{
				f32(mrb.to_f64(args[0])),
				f32(mrb.to_f64(args[1])),
				f32(mrb.to_f64(args[2])),
				f32(mrb.to_f64(args[3])),
				f32(mrb.to_f64(args[4])),
			},
		)
	case:
		return mrb.raise_error(
			state,
			"ArgumentError",
			"arc(): wrong number of arguments (given %d, expected 3, 4, or 5)",
			argc,
		)
	}
}

ruby_arc_get_center :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	if a == nil { return create_vector2({0, 0}) }
	return create_vector2({a.cx, a.cy})
}

ruby_arc_get_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	return mrb.word_boxing_float_value(state, a == nil ? 0 : f64(a.cx))
}

ruby_arc_get_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	return mrb.word_boxing_float_value(state, a == nil ? 0 : f64(a.cy))
}

ruby_arc_get_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	return mrb.word_boxing_float_value(state, a == nil ? 0 : f64(a.r))
}

ruby_arc_get_start :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	return mrb.word_boxing_float_value(state, a == nil ? 0 : f64(a.start))
}

ruby_arc_get_sweep :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	return mrb.word_boxing_float_value(state, a == nil ? 0 : f64(a.sweep))
}

ruby_arc_set_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	a := extract_native(Arc, self)
	if a != nil { a.cx = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_arc_set_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	a := extract_native(Arc, self)
	if a != nil { a.cy = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_arc_set_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	a := extract_native(Arc, self)
	if a != nil { a.r = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_arc_set_start :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	a := extract_native(Arc, self)
	if a != nil { a.start = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_arc_set_sweep :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	a := extract_native(Arc, self)
	if a != nil { a.sweep = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_arc_contains :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p_val: mrb.Value
	mrb.get_args(state, "o", &p_val)
	a := extract_native(Arc, self)
	p := extract_native(rl.Vector2, p_val)
	if a == nil || p == nil { return mrb.FALSE }
	dx := p.x - a.cx
	dy := p.y - a.cy
	if dx * dx + dy * dy > a.r * a.r { return mrb.FALSE }
	if abs(a.sweep) >= 2 * math.PI { return mrb.TRUE } 	// full disc

	// signed offset of point angle from start, normalized to the sweep's
	// direction so negative sweeps work.
	ang := math.atan2(dy, dx)
	delta := ang - a.start
	for delta < 0 { delta += 2 * math.PI }
	for delta >= 2 * math.PI { delta -= 2 * math.PI }
	if a.sweep >= 0 { return delta <= a.sweep ? mrb.TRUE : mrb.FALSE }
	return (2 * math.PI - delta) <= -a.sweep ? mrb.TRUE : mrb.FALSE
}

ruby_arc_sample_point :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a := extract_native(Arc, self)
	if a == nil { return create_vector2({0, 0}) }
	theta := a.start + rand.float32() * a.sweep
	radius := math.sqrt(rand.float32()) * a.r // area-correct
	return create_vector2({a.cx + radius * math.cos(theta), a.cy + radius * math.sin(theta)})
}

ruby_arc_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	a := extract_native(Arc, self)
	if a == nil { return mrb.NIL }

	offset := _parse_offset_kwarg(state, kwargs)
	draw_arc(
		pos = {a.cx + offset.x, a.cy + offset.y},
		radius = a.r,
		start = a.start,
		sweep = a.sweep,
		color = _parse_color_kwarg(state, kwargs),
		thickness = _parse_f32_kwarg(state, kwargs, sym.thickness, 1),
		filled = _parse_bool_kwarg(state, kwargs, sym.filled),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
}

ruby_arc_add :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	a := extract_native(Arc, self)
	v := extract_native(rl.Vector2, other)
	if a == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Arc#+ expects a Vector2") }
	return create_arc({a.cx + v.x, a.cy + v.y, a.r, a.start, a.sweep})
}

ruby_arc_subtract :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	a := extract_native(Arc, self)
	v := extract_native(rl.Vector2, other)
	if a == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Arc#- expects a Vector2") }
	return create_arc({a.cx - v.x, a.cy - v.y, a.r, a.start, a.sweep})
}

setup_arc :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Arc")
	mrb.define_method(g.mrb_state, c, "+", cast(rawptr)ruby_arc_add, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "-", cast(rawptr)ruby_arc_subtract, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "center", cast(rawptr)ruby_arc_get_center, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_arc_get_x, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_arc_get_y, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "r", cast(rawptr)ruby_arc_get_r, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "radius", cast(rawptr)ruby_arc_get_r, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "start", cast(rawptr)ruby_arc_get_start, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "sweep", cast(rawptr)ruby_arc_get_sweep, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "x=", cast(rawptr)ruby_arc_set_x, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "y=", cast(rawptr)ruby_arc_set_y, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "r=", cast(rawptr)ruby_arc_set_r, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "radius=", cast(rawptr)ruby_arc_set_r, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "start=", cast(rawptr)ruby_arc_set_start, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "sweep=", cast(rawptr)ruby_arc_set_sweep, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "contains?", cast(rawptr)ruby_arc_contains, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "sample_point", cast(rawptr)ruby_arc_sample_point, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_arc_draw, mrb.ARGS_OPT(1))
}

draw_arc :: proc(
	pos: rl.Vector2,
	radius: f32,
	start: f32,
	sweep: f32,
	color: rl.Color = {255, 255, 255, 255},
	thickness: f32 = 1,
	filled: bool = false,
	clip: Maybe(rl.Rectangle) = nil,
) {
	p := lin.floor(pos)
	// segment count scaled to sweep, matching DrawCircleV's 36-seg full circle
	segs := max(i32(36 * abs(sweep) / (2 * math.PI)), 3)
	start_deg := start * rl.RAD2DEG
	end_deg := (start + sweep) * rl.RAD2DEG

	did_clip := _clip(clip, p)

	if filled {
		rl.DrawCircleSector(p, radius, start_deg, end_deg, segs, color)
	} else {
		// DrawRing (filled annulus) batches with other shape draws; line
		// primitives would force a batch flush -> extra draw call.
		inner := max(radius - thickness, 0)
		rl.DrawRing(p, inner, radius, start_deg, end_deg, segs, color)
	}

	if did_clip { rl.EndScissorMode() }
}
