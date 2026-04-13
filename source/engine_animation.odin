package engine

import "core:c"
import mrb "lib:mruby"

Animation_Mode :: enum u8 {
	LOOP      = 0,
	ONCE      = 1,
	PING_PONG = 2,
}

Anim :: struct {
	timer:              f32,
	interval:           f32,
	original_interval:  f32,
	current_index:      i32,
	direction:          i32,
	original_direction: i32,
	value_count:        i32,
	mode:               Animation_Mode,
	values:             mrb.Value,
}

ruby_anim_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		anim := cast(^Anim)ptr
		if anim.values != mrb.NIL { mrb.gc_unregister(state, anim.values) }
		mrb.free(state, ptr)
	}
}

create_anim :: proc(interval: f32, direction: i32, mode: Animation_Mode, values: mrb.Value) -> mrb.Value {
	// Convert ranges to arrays (games often pass 0..3 instead of [0,1,2,3])
	actual_values := values
	if !mrb.array_p(values) && values != mrb.NIL {
		// Try to convert to array via to_a
		actual_values = mrb.funcall(g.mrb_state, values, "to_a", 0)
	}

	value_count := i32(mrb.ary_len(actual_values))

	a := Anim {
		timer              = interval,
		interval           = interval,
		original_interval  = interval,
		current_index      = 0,
		direction          = direction,
		original_direction = direction,
		value_count        = value_count,
		mode               = mode,
		values             = actual_values,
	}
	anim_ptr := mrb.alloc(g.mrb_state, a)

	mrb.gc_register(g.mrb_state, actual_values)

	anim_class := mrb.class_get(g.mrb_state, "Anim")
	ruby_obj := mrb.obj_new(g.mrb_state, anim_class, 0, nil)
	mrb.data_init(ruby_obj, anim_ptr, NATIVE_TO_MRUBY_TYPE[Anim])

	return ruby_obj
}

// RUBY FUNCTION: anim(interval:, values:, direction: 1, mode: Anim::LOOP) -> returns Anim object
// @engine_method: name="anim", arity=1
ruby_anim :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "H", &kwargs)

	// required: interval
	interval_val := mrb.kwarg(state, kwargs, sym.interval)
	if interval_val == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "Animations must have `interval`")
	}
	interval := f32(mrb.to_f64(interval_val))

	// required: values
	values := mrb.kwarg(state, kwargs, sym.values)
	if values == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "Animations must have `values`")
	}

	// optional: direction (default +1)
	direction: i32 = 1
	dir_val := mrb.kwarg(state, kwargs, sym.direction)
	if dir_val != mrb.NIL { direction = i32(mrb.integer(dir_val)) }

	// optional: mode (default LOOP = 0)
	mode: Animation_Mode = .LOOP
	mode_val := mrb.kwarg(state, kwargs, sym.mode)
	if mode_val != mrb.NIL { mode = Animation_Mode(mrb.integer(mode_val)) }

	return create_anim(interval, direction, mode, values)
}

ruby_anim_update :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	dt_val: mrb.Value
	mrb.get_args(state, "o", &dt_val)

	anim := extract_native(Anim, self)
	if anim == nil { return mrb.NIL }

	dt := f32(mrb.to_f64(dt_val))
	anim.timer -= dt
	if anim.timer > 0 { return mrb.NIL }

	anim.timer += anim.interval

	// Guard against empty animations
	if anim.value_count <= 0 { return mrb.NIL }

	switch anim.mode {
	case .LOOP:
		anim.current_index = (anim.current_index + anim.direction) %% anim.value_count
	case .PING_PONG:
		anim.current_index += anim.direction
		if anim.current_index >= anim.value_count || anim.current_index < 0 {
			anim.direction = -anim.direction
			anim.current_index = clamp(anim.current_index, 0, anim.value_count - 1)
		}
	case .ONCE:
		anim.current_index = clamp(anim.current_index + anim.direction, 0, anim.value_count - 1)
	}

	return mrb.NIL
}

ruby_anim_reset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	anim := extract_native(Anim, self)
	if anim == nil { return mrb.NIL }

	anim.direction = anim.original_direction
	anim.timer = anim.original_interval
	anim.current_index = 0

	return mrb.NIL
}

ruby_anim_current :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.NIL }
	return mrb.ary_entry(anim.values, c.int(anim.current_index))
}

ruby_anim_index :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.boxing_int_value(state, 0) }
	return mrb.boxing_int_value(state, anim.current_index)
}

ruby_anim_values :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.ary_new(state) }
	return anim.values
}

ruby_anim_direction :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.boxing_int_value(state, 1) }
	return mrb.boxing_int_value(state, anim.direction)
}

ruby_anim_set_direction :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	dir: i32
	mrb.get_args(state, "i", &dir)

	anim := extract_native(Anim, self)
	if anim != nil { anim.direction = dir }

	return mrb.boxing_int_value(state, dir)
}

ruby_anim_interval :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, f64(anim.interval))
}

ruby_anim_set_interval :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	interval: f64
	mrb.get_args(state, "f", &interval)

	anim := extract_native(Anim, self)
	if anim != nil {
		anim.interval = f32(interval)
		anim.original_interval = f32(interval)
	}

	return mrb.word_boxing_float_value(state, interval)
}

ruby_anim_mode :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	anim := extract_native(Anim, self)
	if anim == nil { return mrb.boxing_int_value(state, 0) }
	return mrb.boxing_int_value(state, i32(anim.mode))
}

ruby_anim_set_mode :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	mode: i32
	mrb.get_args(state, "i", &mode)

	anim := extract_native(Anim, self)
	if anim != nil { anim.mode = Animation_Mode(mode) }

	return mrb.boxing_int_value(state, mode)
}

ruby_anim_progress :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	anim := extract_native(Anim, self)
	if anim == nil { return mrb.word_boxing_float_value(state, 0) }
	if anim.value_count <= 1 { return mrb.word_boxing_float_value(state, 0) }

	progress: f64

	switch anim.mode {
	case .LOOP, .ONCE:
		progress = f64(anim.current_index) / f64(anim.value_count - 1)
	case .PING_PONG:
		if anim.direction > 0 {
			progress = f64(anim.current_index) / f64(anim.value_count - 1)
		} else {
			progress = 1.0 - (f64(anim.current_index) / f64(anim.value_count - 1))
		}
	}

	return mrb.word_boxing_float_value(state, progress)
}

ruby_anim_last :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	anim := extract_native(Anim, self)
	if anim == nil { return mrb.FALSE }

	last: bool
	if anim.direction > 0 {
		last = anim.current_index == anim.value_count - 1
	} else {
		last = anim.current_index == 0
	}

	return last ? mrb.TRUE : mrb.FALSE
}

setup_animation :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Anim")

	mrb.define_method(g.mrb_state, c, "update", cast(rawptr)ruby_anim_update, 1)
	mrb.define_method(g.mrb_state, c, "reset", cast(rawptr)ruby_anim_reset, 0)
	mrb.define_method(g.mrb_state, c, "current", cast(rawptr)ruby_anim_current, 0)
	mrb.define_method(g.mrb_state, c, "index", cast(rawptr)ruby_anim_index, 0)
	mrb.define_method(g.mrb_state, c, "values", cast(rawptr)ruby_anim_values, 0)
	mrb.define_method(g.mrb_state, c, "direction", cast(rawptr)ruby_anim_direction, 0)
	mrb.define_method(g.mrb_state, c, "direction=", cast(rawptr)ruby_anim_set_direction, 1)
	mrb.define_method(g.mrb_state, c, "interval", cast(rawptr)ruby_anim_interval, 0)
	mrb.define_method(g.mrb_state, c, "interval=", cast(rawptr)ruby_anim_set_interval, 1)
	mrb.define_method(g.mrb_state, c, "mode", cast(rawptr)ruby_anim_mode, 0)
	mrb.define_method(g.mrb_state, c, "mode=", cast(rawptr)ruby_anim_set_mode, 1)
	mrb.define_method(g.mrb_state, c, "progress", cast(rawptr)ruby_anim_progress, 0)
	mrb.define_method(g.mrb_state, c, "last?", cast(rawptr)ruby_anim_last, 0)
}
