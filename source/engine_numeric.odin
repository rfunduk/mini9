package engine

import "core:math"
import "core:math/rand"
import mrb "lib:mruby"

// RUBY METHOD: number.move_toward(target, delta) -> moves number toward target by delta amount
ruby_num_move_toward :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	target, delta: f64
	mrb.get_args(state, "ff", &target, &delta)

	current := mrb.to_f64(self)

	if math.abs(target - current) <= delta {
		return mrb.word_boxing_float_value(state, target)
	}

	if current < target {
		return mrb.word_boxing_float_value(state, current + delta)
	} else {
		return mrb.word_boxing_float_value(state, current - delta)
	}
}

// RUBY METHOD: number.lerp(target, weight) -> linear interpolation between numbers
ruby_num_lerp :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	target, weight: f64
	mrb.get_args(state, "ff", &target, &weight)

	current := mrb.to_f64(self)

	result := current + (target - current) * weight
	return mrb.word_boxing_float_value(state, result)
}

// RUBY METHOD: number.zero_approx?(epsilon = 1e-5) -> checks if number is approximately zero
ruby_num_zero_approx :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	epsilon: f64
	argc := mrb.get_args(state, "|f", &epsilon)

	current := mrb.to_f64(self)
	epsilon = argc == 1 ? epsilon : 1e-5

	return math.abs(current) <= epsilon ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: number.equal_approx?(other, epsilon = 1e-5) -> checks if numbers are approximately equal
ruby_num_equal_approx :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other, epsilon: f64
	argc := mrb.get_args(state, "f|f", &other, &epsilon)

	current := mrb.to_f64(self)
	epsilon = argc > 1 ? epsilon : 1e-5

	return math.abs(current - other) <= epsilon ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: number.sign -> returns -1, 0, or 1 based on sign
ruby_num_sign :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	current := mrb.to_f64(self)

	if current > 0 {
		return mrb.word_boxing_float_value(state, 1.0)
	} else if current < 0 {
		return mrb.word_boxing_float_value(state, -1.0)
	} else {
		return mrb.word_boxing_float_value(state, 0.0)
	}
}

// RUBY METHOD: number.clamp(min, max) -> clamps number between min and max
ruby_num_clamp :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	min, max: f64
	mrb.get_args(state, "ff", &min, &max)
	current := mrb.to_f64(self)
	result := math.clamp(current, min, max)
	return mrb.word_boxing_float_value(state, result)
}

// RUBY METHOD: number.wrapf(min, max) -> wraps number between min and max
ruby_num_wrapf :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	min, max: f64
	mrb.get_args(state, "ff", &min, &max)
	current := mrb.to_f64(self)

	range := max - min
	if range <= 0 {
		return mrb.word_boxing_float_value(state, min)
	}

	result := current - (range * math.floor((current - min) / range))
	return mrb.word_boxing_float_value(state, result)
}

// RUBY METHOD: number.grid_pos(width, height=width) -> converts index to grid x,y coordinates
ruby_num_grid_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	width, height: i32
	height_given: bool
	mrb.get_args(state, "i|i?", &width, &height, &height_given)

	if !height_given { height = width }

	index := i32(mrb.to_f64(self))

	// bounds checking - return nil if index is out of bounds
	if index < 0 || index >= width * height {
		return mrb.NIL
	}

	x := index % width
	y := index / width

	return create_vector2({f32(x), f32(y)})
}

// RUBY FUNCTION: randf_range(from, to) -> returns random float between from and to
// @engine_method: name="randf_range", aspec=ARGS_REQ(2)
ruby_randf_range :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	from, to: f64
	mrb.get_args(state, "ff", &from, &to)

	result := rand.float64_range(from, to)
	return mrb.word_boxing_float_value(state, result)
}

// RUBY FUNCTION: inverse_lerp(a, b, v) -> where v falls in [a,b] as a 0..1 weight (unclamped)
// @engine_method: name="inverse_lerp", aspec=ARGS_REQ(3)
ruby_inverse_lerp :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a, b, v: f64
	mrb.get_args(state, "fff", &a, &b, &v)

	// a == b: degenerate range, division by zero. Match Godot — return 0.
	if a == b { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, (v - a) / (b - a))
}

// RUBY FUNCTION: remap(v, in_lo, in_hi, out_lo, out_hi) -> v mapped from input range to output range (unclamped)
// @engine_method: name="remap", aspec=ARGS_REQ(5)
ruby_remap :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v, in_lo, in_hi, out_lo, out_hi: f64
	mrb.get_args(state, "fffff", &v, &in_lo, &in_hi, &out_lo, &out_hi)

	t := in_lo == in_hi ? 0 : (v - in_lo) / (in_hi - in_lo)
	return mrb.word_boxing_float_value(state, out_lo + (out_hi - out_lo) * t)
}

setup_numeric :: proc() {
	c := mrb.class_get(g.mrb_state, "Numeric")

	mrb.define_method(g.mrb_state, c, "move_toward", cast(rawptr)ruby_num_move_toward, mrb.ARGS_REQ(2))
	mrb.define_method(g.mrb_state, c, "lerp", cast(rawptr)ruby_num_lerp, mrb.ARGS_REQ(2))
	mrb.define_method(g.mrb_state, c, "zero_approx?", cast(rawptr)ruby_num_zero_approx, mrb.ARGS_OPT(1))

	mrb.define_method(g.mrb_state, c, "equal_approx?", cast(rawptr)ruby_num_equal_approx, mrb.ARGS_ARG(1, 1))

	mrb.define_method(g.mrb_state, c, "sign", cast(rawptr)ruby_num_sign, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "clamp", cast(rawptr)ruby_num_clamp, mrb.ARGS_REQ(2))
	mrb.define_method(g.mrb_state, c, "wrapf", cast(rawptr)ruby_num_wrapf, mrb.ARGS_REQ(2))
	mrb.define_method(g.mrb_state, c, "grid_pos", cast(rawptr)ruby_num_grid_pos, mrb.ARGS_ARG(1, 1))

}
