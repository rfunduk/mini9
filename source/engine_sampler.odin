package engine

import "core:math/rand"
import mrb "lib:mruby"
import rl "lib:raylib"

Sampler_Kind :: enum {
	Numeric,
	V2,
}

Sampler :: struct {
	kind: Sampler_Kind,
	f_lo: f32,
	f_hi: f32,
	v_lo: rl.Vector2,
	v_hi: rl.Vector2,
}

ruby_sampler_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_sampler :: proc(s: Sampler) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, s)
	class := mrb.class_get(g.mrb_state, "Sampler")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Sampler])
	return ruby_obj
}

sampler_sample_f :: #force_inline proc(s: ^Sampler) -> f32 {
	if s.kind == .Numeric {
		return s.f_lo + rand.float32() * (s.f_hi - s.f_lo)
	}
	return 0
}

sampler_sample_v2 :: #force_inline proc(s: ^Sampler) -> rl.Vector2 {
	if s.kind == .V2 {
		return {
			s.v_lo.x + rand.float32() * (s.v_hi.x - s.v_lo.x),
			s.v_lo.y + rand.float32() * (s.v_hi.y - s.v_lo.y),
		}
	}
	return {0, 0}
}

// RUBY FUNCTION: sampler(lo, hi) -> Sampler
// @engine_method: name="sampler", aspec=ARGS_REQ(2)
ruby_sampler :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	lo, hi: mrb.Value
	mrb.get_args(state, "oo", &lo, &hi)

	if is_native(rl.Vector2, lo) && is_native(rl.Vector2, hi) {
		v_lo := extract_native(rl.Vector2, lo)
		v_hi := extract_native(rl.Vector2, hi)
		return create_sampler({kind = .V2, v_lo = v_lo^, v_hi = v_hi^})
	}

	if mrb.integer_p(lo) || mrb.float_p(lo) {
		return create_sampler({kind = .Numeric, f_lo = f32(mrb.to_f64(lo)), f_hi = f32(mrb.to_f64(hi))})
	}

	return mrb.raise_error(
		state,
		"ArgumentError",
		"sampler(lo, hi): args must both be Numeric or both Vector2",
	)
}

ruby_sampler_lo :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	s := extract_native(Sampler, self)
	if s == nil { return mrb.NIL }
	if s.kind == .V2 { return create_vector2(s.v_lo) }
	return mrb.word_boxing_float_value(state, f64(s.f_lo))
}

ruby_sampler_hi :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	s := extract_native(Sampler, self)
	if s == nil { return mrb.NIL }
	if s.kind == .V2 { return create_vector2(s.v_hi) }
	return mrb.word_boxing_float_value(state, f64(s.f_hi))
}

setup_sampler :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Sampler")
	mrb.define_method(g.mrb_state, c, "lo", cast(rawptr)ruby_sampler_lo, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "hi", cast(rawptr)ruby_sampler_hi, mrb.ARGS_NONE)
}
