package engine

import "core:log"
import mrb "lib:mruby"

@(private = "file")
timers: [dynamic]^Timer_Instance

Timer_Instance :: struct {
	ruby_obj:  mrb.Value,
	block:     mrb.Value,
	this_obj:  mrb.Value, // NIL until init(parent) called
	interval:  f64,
	elapsed:   f64,
	repeating: bool,
	finished:  bool,
	cancelled: bool,
}

ruby_timer_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr == nil { return }
	t := cast(^Timer_Instance)ptr
	if t.block != mrb.NIL { mrb.gc_unregister(state, t.block) }
	if t.this_obj != mrb.NIL { mrb.gc_unregister(state, t.this_obj) }
	mrb.free(state, ptr)
}

create_timer :: proc(interval: f64, block: mrb.Value, repeating: bool) -> mrb.Value {
	t := Timer_Instance {
		block     = block,
		this_obj  = mrb.NIL,
		interval  = interval,
		elapsed   = 0,
		repeating = repeating,
	}
	tptr := mrb.alloc(g.mrb_state, t)

	cls := mrb.class_get(g.mrb_state, "Timer")
	ruby_obj := mrb.obj_new(g.mrb_state, cls, 0, nil)
	mrb.data_init(ruby_obj, tptr, NATIVE_TO_MRUBY_TYPE[Timer_Instance])
	tptr.ruby_obj = ruby_obj

	mrb.gc_register(g.mrb_state, ruby_obj)
	if block != mrb.NIL { mrb.gc_register(g.mrb_state, block) }

	append(&timers, tptr)
	return ruby_obj
}

// RUBY FUNCTION: after(seconds) { |this| ... } -> Timer
// @engine_method: name="after", aspec=ARGS_REQ(1)|ARGS_BLOCK
ruby_after :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	seconds: f64
	block: mrb.Value
	mrb.get_args(state, "f&", &seconds, &block)
	if block == mrb.NIL || !mrb.proc_p(block) {
		return mrb.raise_error(state, "ArgumentError", "after requires a block")
	}
	if seconds < 0 {
		return mrb.raise_error(state, "ArgumentError", "after seconds must be >= 0")
	}
	return create_timer(seconds, block, false)
}

// RUBY FUNCTION: every(seconds, leading: false) { |this| ... } -> Timer
// @engine_method: name="every", aspec=ARGS_ARG(1,1)|ARGS_BLOCK
ruby_every :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	seconds: f64
	kwargs, block: mrb.Value
	argc := mrb.get_args(state, "f|H&", &seconds, &kwargs, &block)
	if block == mrb.NIL || !mrb.proc_p(block) {
		return mrb.raise_error(state, "ArgumentError", "every requires a block")
	}
	if seconds <= 0 {
		return mrb.raise_error(state, "ArgumentError", "every seconds must be > 0")
	}

	leading := false
	if argc >= 2 {
		val := mrb.kwarg(state, kwargs, sym.leading)
		if val != mrb.NIL { leading = mrb.boolean(val) }
	}

	obj := create_timer(seconds, block, true)
	if leading {
		t := extract_native(Timer_Instance, obj)
		if t != nil { t.elapsed = seconds }
	}
	return obj
}

// Timer._attach(parent) — auto-called by obj() for fields responding to :_attach
ruby_timer_attach :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	this_obj: mrb.Value
	mrb.get_args(state, "o", &this_obj)

	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.NIL }

	if t.this_obj != mrb.NIL { mrb.gc_unregister(state, t.this_obj) }
	t.this_obj = this_obj
	if this_obj != mrb.NIL { mrb.gc_register(state, this_obj) }

	return self
}

ruby_timer_cancel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.NIL }
	if !t.finished {
		t.cancelled = true
		t.finished = true
	}
	return mrb.NIL
}

ruby_timer_cancelled :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.FALSE }
	return t.cancelled ? mrb.TRUE : mrb.FALSE
}

ruby_timer_finished :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.FALSE }
	return t.finished ? mrb.TRUE : mrb.FALSE
}

ruby_timer_repeating :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.FALSE }
	return t.repeating ? mrb.TRUE : mrb.FALSE
}

ruby_timer_interval :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, t.interval)
}

ruby_timer_elapsed :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.word_boxing_float_value(state, 0) }
	return mrb.word_boxing_float_value(state, t.elapsed)
}

ruby_timer_remaining :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Timer_Instance, self)
	if t == nil { return mrb.word_boxing_float_value(state, 0) }
	r := t.interval - t.elapsed
	if r < 0 { r = 0 }
	return mrb.word_boxing_float_value(state, r)
}

// Called once per fixed-timestep tick before user update.
update_timers :: proc() {
	if len(timers) == 0 { return }

	// snapshot length so timers added during a callback don't fire this tick
	n := len(timers)
	for i in 0 ..< n {
		t := timers[i]
		if t.finished { continue }

		t.elapsed += f64(FIXED_DT)
		for t.elapsed >= t.interval && !t.finished {
			fire_timer(t)
			if t.repeating {
				t.elapsed -= t.interval
			} else {
				t.finished = true
			}
		}
	}

	// sweep finished timers, releasing GC pins
	w := 0
	for i in 0 ..< len(timers) {
		t := timers[i]
		if t.finished {
			if t.ruby_obj != mrb.NIL {
				mrb.gc_unregister(g.mrb_state, t.ruby_obj)
				// keep ruby_obj reachable from the Ruby-side handle so accessors
				// still work on a cancelled/finished timer
			}
			if t.block != mrb.NIL {
				mrb.gc_unregister(g.mrb_state, t.block)
				t.block = mrb.NIL
			}
		} else {
			timers[w] = t
			w += 1
		}
	}
	resize(&timers, w)
}

fire_timer :: proc(t: ^Timer_Instance) {
	if t.block == mrb.NIL { return }
	if !dispatch_yield(t.block, t.this_obj, .TIMER_CALLBACK) {
		// callback raised — disable to avoid recurring crash on every tick
		log.warnf("timer callback raised; cancelling timer")
		t.cancelled = true
		t.finished = true
	}
}

setup_timer :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Timer")
	mrb.define_method(g.mrb_state, c, "_attach", cast(rawptr)ruby_timer_attach, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "cancel", cast(rawptr)ruby_timer_cancel, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "cancelled?", cast(rawptr)ruby_timer_cancelled, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "finished?", cast(rawptr)ruby_timer_finished, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "repeating?", cast(rawptr)ruby_timer_repeating, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "interval", cast(rawptr)ruby_timer_interval, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "elapsed", cast(rawptr)ruby_timer_elapsed, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "remaining", cast(rawptr)ruby_timer_remaining, mrb.ARGS_NONE)
}

cleanup_timer :: proc() {
	delete(timers)
}
