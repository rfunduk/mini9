package engine

import "core:math/ease"
import mrb "lib:mruby"

ruby_easing_at :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	t: f64
	easing_int: i32 = 0
	mrb.get_args(state, "f|i", &t, &easing_int)

	if easing_int < i32(min(ease.Ease)) || easing_int > i32(max(ease.Ease)) {
		return mrb.raise_error(state, "ArgumentError", "unknown easing %d", easing_int)
	}

	v := ease.ease(ease.Ease(easing_int), t)
	return mrb.word_boxing_float_value(state, v)
}

setup_easing :: proc() {
	m := mrb.module_get(g.mrb_state, "Easing")
	mrb.define_module_function(g.mrb_state, m, "at", cast(rawptr)ruby_easing_at, -1)
}
