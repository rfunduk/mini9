package engine

import "core:log"
import "core:os"
import mrb "lib:mruby"

init_ruby_api :: proc() {
	g.mrb_state = mrb.open()
	if g.mrb_state == nil {
		log.errorf("Failed to set up Ruby VM")
		os.exit(1)
	}

	g.mrb_ctx = mrb.ccontext_new(g.mrb_state)
	if g.mrb_ctx == nil {
		log.errorf("Failed to set up Ruby VM context")
		os.exit(1)
	}

	engine_init_ruby_api()
}

shutdown_ruby :: proc() {
	if g.mrb_ctx != nil {
		mrb.ccontext_free(g.mrb_state, g.mrb_ctx)
		g.mrb_ctx = nil
	}
	if g.mrb_state != nil {
		mrb.close(g.mrb_state)
		g.mrb_state = nil
	}
}

ruby_function_exists :: proc(name: cstring) -> bool {
	if g.mrb_state == nil { return false }
	top := mrb.top_self(g.mrb_state)
	sym := mrb.intern_cstr(g.mrb_state, name)
	return mrb.respond_to(g.mrb_state, top, sym)
}

// to_f64 - extracts numeric value as f64, handling both integers and floats
to_f64 :: #force_inline proc(val: mrb.Value) -> f64 {
	if mrb.integer_p(val) {
		return f64(mrb.integer(val))
	} else if mrb.float_p(val) {
		return mrb.float(val)
	}
	return 0.0
}
