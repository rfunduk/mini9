package engine

import "core:log"
import mrb "lib:mruby"
import rl "lib:raylib"

// Resolve the game's lifecycle callbacks once, after main.rb has loaded.
// Capture each as a Method, gc_register it, stash it, then undef the name
// off Object so a stray `x.update` raises a clean NoMethodError
determine_game_callbacks :: proc() {
	if g.mrb_state == nil { return }

	top := mrb.top_self(g.mrb_state)

	esym := mrb.intern_cstr(g.mrb_state, "event")
	if mrb.respond_to(g.mrb_state, top, esym) {
		arity := i32(mrb.method_arity(g.mrb_state, top, esym))
		if arity == 0 {
			log.errorf("[ENGINE] ERROR: Callback `event` defined with invalid arity 0, expected 1")
			panic("EXITING")
		}
	}

	// NB: mrb.funcall's #c_vararg passes Odin `any` (fat pointer) into C
	// varargs that expect mrb_value-by-value — ABI mismatch, corrupts the
	// stack (intermittent segfault). Use funcall_argv with an explicit
	// Value array for anything that takes args.
	sym_class := mrb.intern_cstr(g.mrb_state, "class")
	sym_method := mrb.intern_cstr(g.mrb_state, "method")
	sym_send := mrb.intern_cstr(g.mrb_state, "send")
	undef_sym := mrb.symbol_value(mrb.intern_cstr(g.mrb_state, "undef_method"))

	obj_class := mrb.funcall_argv(g.mrb_state, top, sym_class, 0, nil) // main.class == Object

	captures := [?]struct {
		name: cstring,
		slot: ^mrb.Value,
	}{{"update", &g.update_proc}, {"draw", &g.draw_proc}, {"ui", &g.ui_proc}}
	for c in captures {
		// on hot reload this runs a second time — drop the previously captured
		// Method's root before overwriting it, or each reload leaks one.
		if c.slot^ != mrb.NIL { mrb.gc_unregister(g.mrb_state, c.slot^) }
		c.slot^ = mrb.NIL
		nsym := mrb.symbol_value(mrb.intern_cstr(g.mrb_state, c.name))
		if !mrb.respond_to(g.mrb_state, top, mrb.symbol(nsym)) { continue }

		method_args := [1]mrb.Value{nsym}
		c.slot^ = mrb.funcall_argv(g.mrb_state, top, sym_method, 1, raw_data(method_args[:]))
		mrb.gc_register(g.mrb_state, c.slot^)

		undef_args := [2]mrb.Value{undef_sym, nsym}
		mrb.funcall_argv(g.mrb_state, obj_class, sym_send, 2, raw_data(undef_args[:]))
	}
}

call_user_events :: proc() {
	if g.mrb_state == nil { return }
	event_queue := mrb.gv_get(g.mrb_state, mrb.intern_cstr(g.mrb_state, "$event_queue"))
	dispatch_funcall(event_queue, "process_events", 0, nil, .EVENT)
}

call_user_tasks :: proc() {
	if g.mrb_state == nil { return }
	tasks := mrb.gv_get(g.mrb_state, mrb.intern_cstr(g.mrb_state, "$tasks"))
	if tasks == mrb.NIL { return }
	deadline := rl.GetTime() + TASK_BUDGET_SECONDS
	args := [1]mrb.Value{mrb.word_boxing_float_value(g.mrb_state, deadline)}
	dispatch_funcall(tasks, "tick", 1, raw_data(args[:]), .TASK)
}

call_user_update :: proc() {
	if g.mrb_state == nil || g.update_proc == mrb.NIL { return }
	dispatch_funcall(g.update_proc, "call", 0, nil, .UPDATE)
}

call_user_draw :: proc() {
	if g.clear_color.a != 0 { rl.ClearBackground(g.clear_color) }
	if g.mrb_state == nil || g.draw_proc == mrb.NIL { return }
	dispatch_funcall(g.draw_proc, "call", 0, nil, .DRAW)
}

call_user_ui :: proc() {
	if g.mrb_state == nil || g.ui_proc == mrb.NIL { return }
	dispatch_funcall(g.ui_proc, "call", 0, nil, .UI)
}
