package engine

import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

ruby_vector2_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_vector2 :: proc(v: rl.Vector2) -> mrb.Value {
	vec_ptr := mrb.alloc(g.mrb_state, v)

	vector_class := mrb.class_get(g.mrb_state, "Vector2")
	ruby_obj := mrb.obj_new(g.mrb_state, vector_class, 0, nil)
	mrb.data_init(ruby_obj, vec_ptr, NATIVE_TO_MRUBY_TYPE[rl.Vector2])

	return ruby_obj
}

// RUBY FUNCTION: v2(x, y) -> returns Vector2 object
// @engine_method: name="v2", arity=-1
ruby_v2 :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	x, y: f64
	argc := mrb.get_args(state, "|f|f", &x, &y)

	if argc == 0 {
		x = 0
		y = 0
	} else if argc == 1 {
		y = x
	}

	return create_vector2(rl.Vector2{f32(x), f32(y)})
}

ruby_vector2_get_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	vec := extract_native(rl.Vector2, self)
	return mrb.word_boxing_float_value(state, vec == nil ? 0 : f64(vec.x))
}

ruby_vector2_get_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	vec := extract_native(rl.Vector2, self)
	return mrb.word_boxing_float_value(state, vec == nil ? 0 : f64(vec.y))
}

ruby_vector2_set_x :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new_x: f64
	mrb.get_args(state, "f", &new_x)

	old_vec := extract_native(rl.Vector2, self)
	if old_vec == nil { return mrb.NIL }

	new_vec_ptr := mrb.alloc(g.mrb_state, rl.Vector2{f32(new_x), old_vec.y})
	mrb.data_init(self, new_vec_ptr, NATIVE_TO_MRUBY_TYPE[rl.Vector2])

	return mrb.word_boxing_float_value(state, new_x)
}

ruby_vector2_set_y :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	new_y: f64
	mrb.get_args(state, "f", &new_y)

	old_vec := extract_native(rl.Vector2, self)
	if old_vec == nil { return mrb.NIL }

	new_vec_ptr := mrb.alloc(g.mrb_state, rl.Vector2{old_vec.x, f32(new_y)})
	mrb.data_init(self, new_vec_ptr, NATIVE_TO_MRUBY_TYPE[rl.Vector2])

	return mrb.word_boxing_float_value(state, new_y)
}

ruby_vector2_add :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ + other_vec^)
}

ruby_vector2_subtract :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ - other_vec^)
}

ruby_vector2_unary_minus :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(self_vec^ * -1)
}

ruby_vector2_multiply :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ * other_vec^)
}

ruby_vector2_multiply_scalar :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	scalar: f64
	mrb.get_args(state, "f", &scalar)

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ * f32(scalar))
}

ruby_vector2_divide :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ / other_vec^)
}

ruby_vector2_divide_scalar :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	scalar: f64
	mrb.get_args(state, "f", &scalar)

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }

	return create_vector2(self_vec^ / f32(scalar))
}

ruby_vector2_clamp :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	min: mrb.Value
	max: mrb.Value
	mrb.get_args(state, "o|o", &min, &max)

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }

	min_vec := extract_native(rl.Vector2, min)

	clamped: rl.Vector2
	if max == mrb.NIL {
		clamped = lin.clamp(self_vec^, -lin.abs(min_vec^), lin.abs(min_vec^))
	} else {
		max_vec := extract_native(rl.Vector2, max)
		clamped = lin.clamp(self_vec^, min_vec^, max_vec^)
	}

	return create_vector2(clamped)
}

ruby_vector2_floor :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(lin.floor(self_vec^))
}

ruby_vector2_ceil :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(lin.ceil(self_vec^))
}

ruby_vector2_round :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(lin.round(self_vec^))
}

ruby_vector2_is_equal_approx :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)

	if self_vec == nil || other_vec == nil { return mrb.FALSE }

	epsilon: f32 = 0.00001
	equal := abs(self_vec.x - other_vec.x) < epsilon && abs(self_vec.y - other_vec.y) < epsilon
	return equal ? mrb.TRUE : mrb.FALSE
}

ruby_vector2_is_zero_approx :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.FALSE }

	epsilon: f32 = 0.00001
	zero := abs(self_vec.x) < epsilon && abs(self_vec.y) < epsilon
	return zero ? mrb.TRUE : mrb.FALSE
}

ruby_vector2_length :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, f64(lin.length(self_vec^)))
}

ruby_vector2_length_squared :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, f64(lin.length2(self_vec^)))
}

ruby_vector2_normalized :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(vector2_normalized(self_vec^))
}

vector2_normalized :: proc(v: rl.Vector2) -> rl.Vector2 {
	len2 := lin.length2(v)
	if len2 < 0.001 { return {0, 0} }
	return v / math.sqrt(len2)
}

ruby_vector2_rotated :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	angle: f64
	mrb.get_args(state, "f", &angle)

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }

	rad := f32(angle)
	cos_a := math.cos(rad)
	sin_a := math.sin(rad)

	rotated := rl.Vector2{self_vec.x * cos_a - self_vec.y * sin_a, self_vec.x * sin_a + self_vec.y * cos_a}
	return create_vector2(rotated)
}

ruby_vector2_distance_to :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.word_boxing_float_value(state, 0) }

	return mrb.word_boxing_float_value(state, f64(lin.distance(self_vec^, other_vec^)))
}

ruby_vector2_direction_to :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)
	if self_vec == nil || other_vec == nil { return mrb.NIL }

	return create_vector2(lin.normalize0(other_vec^ - self_vec^))
}

ruby_vector2_move_toward :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	to_val: mrb.Value
	delta64: f64
	mrb.get_args(state, "of", &to_val, &delta64)

	self_vec := extract_native(rl.Vector2, self)
	to_vec := extract_native(rl.Vector2, to_val)
	delta := f32(delta64)

	if self_vec == nil || to_vec == nil {
		return mrb.raise_error(state, "TypeError", "move_toward: argument must be a Vector2")
	}

	len := lin.length(to_vec^ - self_vec^)
	epsilon: f32 = 0.00001

	if len <= delta || len < epsilon {
		return create_vector2(to_vec^)
	} else {
		w := min(delta / len, 1.0)
		return create_vector2(lin.lerp(self_vec^, to_vec^, rl.Vector2{w, w}))
	}
}

ruby_vector2_sign :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(lin.sign(self_vec^))
}

ruby_vector2_lerp :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	to_val: mrb.Value
	weight: f64
	mrb.get_args(state, "of", &to_val, &weight)

	self_vec := extract_native(rl.Vector2, self)
	to_vec := extract_native(rl.Vector2, to_val)
	if self_vec == nil || to_vec == nil { return mrb.NIL }

	w := clamp(f32(weight), 0, 1)
	return create_vector2(lin.lerp(self_vec^, to_vec^, rl.Vector2{w, w}))
}

ruby_vector2_abs :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }
	return create_vector2(lin.abs(self_vec^))
}

ruby_vector2_angle :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.word_boxing_float_value(state, 0) }

	angle := math.atan2(self_vec.y, self_vec.x)
	return mrb.word_boxing_float_value(state, f64(angle))
}

ruby_vector2_angle_to :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)

	if self_vec == nil || other_vec == nil { return mrb.word_boxing_float_value(state, 0) }

	angle_self := math.atan2(self_vec.y, self_vec.x)
	angle_other := math.atan2(other_vec.y, other_vec.x)
	angle_diff := angle_other - angle_self

	// normalize to [-π, π]
	for angle_diff > math.PI { angle_diff -= 2 * math.PI }
	for angle_diff < -math.PI { angle_diff += 2 * math.PI }

	return mrb.word_boxing_float_value(state, f64(angle_diff))
}

ruby_vector2_dot :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)

	self_vec := extract_native(rl.Vector2, self)
	other_vec := extract_native(rl.Vector2, other)

	if self_vec == nil || other_vec == nil { return mrb.word_boxing_float_value(state, 0) }

	dot_product := self_vec.x * other_vec.x + self_vec.y * other_vec.y
	return mrb.word_boxing_float_value(state, f64(dot_product))
}

// RUBY METHOD: vector2.grid_index(width, height=width, wrap: false) -> converts x,y coordinates to grid index
ruby_vector2_grid_index :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	width, height: i32
	kwargs: mrb.Value
	argc := mrb.get_args(state, "i|iH", &width, &height, &kwargs)

	// set default height if not provided
	if argc < 2 { height = width }

	// parse wrap kwarg (default false)
	wrap := false
	if kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)
		if "wrap" in hash { wrap = mrb.boolean(hash["wrap"]) }
	}

	self_vec := extract_native(rl.Vector2, self)
	if self_vec == nil { return mrb.NIL }

	x := i32(self_vec.x)
	y := i32(self_vec.y)

	if wrap {
		// wrap coordinates using modulo
		x = ((x % width) + width) % width
		y = ((y % height) + height) % height
	} else {
		// return nil for out-of-bounds coordinates
		if x < 0 || x >= width || y < 0 || y >= height { return mrb.NIL }
	}

	index := y * width + x
	return mrb.boxing_int_value(state, index)
}

setup_vector2 :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Vector2")

	mrb.define_method(g.mrb_state, c, "new", cast(rawptr)ruby_v2, -1)
	mrb.define_method(g.mrb_state, c, "x", cast(rawptr)ruby_vector2_get_x, 0)
	mrb.define_method(g.mrb_state, c, "y", cast(rawptr)ruby_vector2_get_y, 0)
	mrb.define_method(g.mrb_state, c, "x=", cast(rawptr)ruby_vector2_set_x, 1)
	mrb.define_method(g.mrb_state, c, "y=", cast(rawptr)ruby_vector2_set_y, 1)
	mrb.define_method(g.mrb_state, c, "+", cast(rawptr)ruby_vector2_add, 1)
	mrb.define_method(g.mrb_state, c, "-", cast(rawptr)ruby_vector2_subtract, 1)
	mrb.define_method(g.mrb_state, c, "-@", cast(rawptr)ruby_vector2_unary_minus, 0)
	mrb.define_method(g.mrb_state, c, "_multiply", cast(rawptr)ruby_vector2_multiply, 1)
	mrb.define_method(g.mrb_state, c, "_multiply_scalar", cast(rawptr)ruby_vector2_multiply_scalar, 1)
	mrb.define_method(g.mrb_state, c, "_divide", cast(rawptr)ruby_vector2_divide, 1)
	mrb.define_method(g.mrb_state, c, "_divide_scalar", cast(rawptr)ruby_vector2_divide_scalar, 1)
	mrb.define_method(g.mrb_state, c, "clamp", cast(rawptr)ruby_vector2_clamp, 1)
	mrb.define_method(g.mrb_state, c, "floor", cast(rawptr)ruby_vector2_floor, 0)
	mrb.define_method(g.mrb_state, c, "ceil", cast(rawptr)ruby_vector2_ceil, 0)
	mrb.define_method(g.mrb_state, c, "round", cast(rawptr)ruby_vector2_round, 0)
	mrb.define_method(g.mrb_state, c, "is_zero_approx?", cast(rawptr)ruby_vector2_is_zero_approx, 0)
	mrb.define_method(g.mrb_state, c, "is_equal_approx?", cast(rawptr)ruby_vector2_is_equal_approx, 1)
	mrb.define_method(g.mrb_state, c, "length", cast(rawptr)ruby_vector2_length, 0)
	mrb.define_method(g.mrb_state, c, "length_squared", cast(rawptr)ruby_vector2_length_squared, 0)
	mrb.define_method(g.mrb_state, c, "normalized", cast(rawptr)ruby_vector2_normalized, 0)
	mrb.define_method(g.mrb_state, c, "rotated", cast(rawptr)ruby_vector2_rotated, 1)
	mrb.define_method(g.mrb_state, c, "distance_to", cast(rawptr)ruby_vector2_distance_to, 1)
	mrb.define_method(g.mrb_state, c, "direction_to", cast(rawptr)ruby_vector2_direction_to, 1)
	mrb.define_method(g.mrb_state, c, "move_toward", cast(rawptr)ruby_vector2_move_toward, 2)
	mrb.define_method(g.mrb_state, c, "sign", cast(rawptr)ruby_vector2_sign, 0)
	mrb.define_method(g.mrb_state, c, "lerp", cast(rawptr)ruby_vector2_lerp, 2)
	mrb.define_method(g.mrb_state, c, "abs", cast(rawptr)ruby_vector2_abs, 0)
	mrb.define_method(g.mrb_state, c, "angle", cast(rawptr)ruby_vector2_angle, 0)
	mrb.define_method(g.mrb_state, c, "angle_to", cast(rawptr)ruby_vector2_angle_to, 1)
	mrb.define_method(g.mrb_state, c, "dot", cast(rawptr)ruby_vector2_dot, 1)
	mrb.define_method(g.mrb_state, c, "grid_index", cast(rawptr)ruby_vector2_grid_index, -1)

	x_sym := mrb.intern_cstr(g.mrb_state, "x")
	y_sym := mrb.intern_cstr(g.mrb_state, "y")
	mrb.alias_method(g.mrb_state, c, mrb.intern_cstr(g.mrb_state, "w"), x_sym)
	mrb.alias_method(g.mrb_state, c, mrb.intern_cstr(g.mrb_state, "h"), y_sym)
	mrb.alias_method(g.mrb_state, c, mrb.intern_cstr(g.mrb_state, "left"), x_sym)
	mrb.alias_method(g.mrb_state, c, mrb.intern_cstr(g.mrb_state, "top"), y_sym)
}
