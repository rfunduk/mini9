package engine

import "core:log"
import "core:strings"
import mrb "lib:mruby"

ENGINE_DEBUG :: #config(ENGINE_DEBUG, false)

// RUBY FUNCTION: debug(enabled) -> enables/disables debug, gives current with no args
// @engine_method: name="debug", aspec=ARGS_OPT(1)
ruby_debug :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	enabled_val: mrb.Value
	argc := mrb.get_args(state, "|b", &enabled_val)

	if argc == 0 { return (ENGINE_DEBUG || g.debug) ? mrb.TRUE : mrb.FALSE }

	enabled := mrb.boolean(enabled_val)
	g.debug = enabled

	return g.debug ? mrb.TRUE : mrb.FALSE
}


// RUBY FUNCTION: metrics(enabled) -> enables/disables metrics, gives current with no args
// @engine_method: name="metrics", aspec=ARGS_OPT(1)
ruby_metrics :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	enabled_val: mrb.Value
	argc := mrb.get_args(state, "|b", &enabled_val)

	if argc == 0 { return (ENGINE_DEBUG && g.metrics) ? mrb.TRUE : mrb.FALSE }

	enabled := mrb.boolean(enabled_val)
	g.metrics = enabled

	return g.metrics ? mrb.TRUE : mrb.FALSE
}


// RUBY FUNCTION: log(*args) -> logs arguments to console separated by spaces
// @engine_method: name="log", aspec=ARGS_ANY
ruby_log :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	if !(ENGINE_DEBUG || g.debug) { return mrb.NIL }

	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)

	if argc == 0 {
		log.infof("")
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

	output := strings.to_string(builder)
	log.infof(output)

	return mrb.NIL
}
