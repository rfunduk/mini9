package engine

import "core:math"
import "core:math/rand"
import mrb "lib:mruby"
import rl "vendor:raylib"

@(private = "file")
next_shake_id: u32 = 1

Shake_Instance :: struct {
	id:         u32,
	duration:   f32,
	frequency:  f32,
	amplitude:  f32,
	samples:    [dynamic]f32,
	start_time: f64,
	is_active:  bool,
}

ruby_shake_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		shake := cast(^Shake_Instance)ptr
		if shake.samples != nil { delete(shake.samples) }
		mrb.free(state, ptr)
	}
}

create_shake :: proc() -> mrb.Value {
	s := Shake_Instance {
		id         = next_shake_id,
		duration   = 0,
		frequency  = 0,
		amplitude  = 0,
		samples    = make([dynamic]f32),
		start_time = 0,
		is_active  = false,
	}
	next_shake_id += 1
	shake_ptr := mrb.alloc(g.mrb_state, s)

	// add to global shake instances
	append(&g.shake_instances, shake_ptr)

	shake_class := mrb.class_get(g.mrb_state, "Shake")
	ruby_obj := mrb.obj_new(g.mrb_state, shake_class, 0, nil)
	mrb.data_init(ruby_obj, shake_ptr, NATIVE_TO_MRUBY_TYPE[Shake_Instance])

	return ruby_obj
}

// RUBY FUNCTION: shake() -> returns new Shake object
// @engine_method: name="shake", arity=0
ruby_shake :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return create_shake()
}

ruby_shake_shake :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	duration, frequency, amplitude: f64
	mrb.get_args(state, "fff", &duration, &frequency, &amplitude)

	shake := extract_native(Shake_Instance, self)
	if shake == nil { return mrb.NIL }

	// clear existing samples
	clear(&shake.samples)

	// store new shake parameters
	shake.duration = f32(duration)
	shake.frequency = f32(frequency)
	shake.amplitude = f32(amplitude)
	shake.start_time = rl.GetTime()
	shake.is_active = true

	// pre-generate noise samples
	sample_count := int(math.ceil(duration * frequency))
	resize(&shake.samples, sample_count)

	for i in 0 ..< sample_count {
		shake.samples[i] = rand.float32_range(-1, 1)
	}

	return mrb.NIL
}

ruby_shake_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	shake := extract_native(Shake_Instance, self)
	if shake == nil { return create_vector2({0, 0}) }
	if !shake.is_active { return create_vector2({0, 0}) }

	current_time := rl.GetTime()
	elapsed := f32(current_time - shake.start_time)

	if elapsed >= shake.duration {
		shake.is_active = false
		return create_vector2({0, 0})
	}

	// calculate noise value using interpolation between samples
	s := elapsed * shake.frequency
	s0 := int(math.floor_f32(s))
	s1 := s0 + 1

	noise0 := noise_sample(shake, s0)
	noise1 := noise_sample(shake, s1)

	// linear interpolation
	frac := s - f32(s0)
	noise := noise0 + (noise1 - noise0) * frac

	// apply decay function
	decay := (shake.duration - elapsed) / shake.duration

	value := noise * decay * shake.amplitude

	// generate random direction for 2D shake
	angle := rand.float32_range(0, 2 * math.PI)
	offset := rl.Vector2{value * math.cos(angle), value * math.sin(angle)}

	return create_vector2(offset)
}

noise_sample :: proc(shake: ^Shake_Instance, index: int) -> f32 {
	if index < 0 || index >= len(shake.samples) { return 0 }
	return shake.samples[index]
}

update_shake_system :: proc() {
	// clean up inactive shakes periodically
	for instance, i in g.shake_instances {
		if !instance.is_active {
			current_time := rl.GetTime()
			elapsed := f32(current_time - instance.start_time)
			if elapsed >= instance.duration + 1.0 { 	// keep for 1 extra second
				ordered_remove(&g.shake_instances, i)
			}
		}
	}
}

setup_shake :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Shake")
	mrb.define_method(g.mrb_state, c, "shake", cast(rawptr)ruby_shake_shake, 3)
	mrb.define_method(g.mrb_state, c, "offset", cast(rawptr)ruby_shake_offset, 0)
}

cleanup_shake :: proc() {
	delete(g.shake_instances)
}
