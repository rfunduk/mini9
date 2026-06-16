package engine

import "core:fmt"
import "core:strings"
import mrb "lib:mruby"

// RUBY FUNCTION (debug builds only): gc -> forces a full GC and returns live obj count
// @engine_method: name="gc", aspec=ARGS_NONE, debug=true
ruby_gc :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	before := mrb.gc_live(state)
	mrb.full_gc(state)
	after := mrb.gc_live(state)
	fmt.printf("[gc] live %v -> %v (reclaimed %v)\n", before, after, int(before) - int(after))
	return mrb.fixnum_value(mrb.Int(after))
}

// RUBY FUNCTION: metrics(enabled) -> enables/disables metrics, gives current with no args
// @engine_method: name="metrics", aspec=ARGS_OPT(1)
ruby_metrics :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	enabled_val: mrb.Value
	argc := mrb.get_args(state, "|b", &enabled_val)

	if argc == 0 { return g.metrics ? mrb.TRUE : mrb.FALSE }

	enabled := mrb.boolean(enabled_val)
	g.metrics = enabled

	return g.metrics ? mrb.TRUE : mrb.FALSE
}

// RUBY FUNCTION: log(*args) -> logs arguments to console separated by spaces
// @engine_method: name="log", aspec=ARGS_ANY
ruby_log :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)

	if argc == 0 {
		fmt.println()
		return mrb.NIL
	}

	args := (cast([^]mrb.Value)argv)[:argc]

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for i in 0 ..< argc {
		if i > 0 { strings.write_byte(&builder, ' ') }
		formatted := mrb.to_string(state, args[i])
		strings.write_string(&builder, formatted)
	}

	fmt.println(strings.to_string(builder))

	return mrb.NIL
}
