package engine

import "core:log"
import mrb "lib:mruby"
import rl "lib:raylib"

// callback info for checking method existence and arity
Callback_Info :: struct {
	method_name: cstring,
	has_arg:     bool,
	has_flag:    ^bool,
}

// check Ruby function arities using native mruby introspection
determine_game_callbacks :: proc() {
	if g.mrb_state == nil { return }

	callback_infos := [?]Callback_Info {
		{"event", true, nil},
		{"update", false, &g.has_update},
		{"draw", false, &g.has_draw},
		{"ui", false, &g.has_ui},
	}

	top := mrb.top_self(g.mrb_state)

	for &callback in callback_infos {
		sym := mrb.intern_cstr(g.mrb_state, callback.method_name)

		if !mrb.respond_to(g.mrb_state, top, sym) { continue }

		arity := i32(mrb.method_arity(g.mrb_state, top, sym))

		// -2 = undefined, -1 = C func (variable args), >= 0 = num args
		if arity <= -1 { continue }
		if arity == 0 && callback.has_arg {
			log.errorf(
				"[ENGINE] ERROR: Callback `%s` defined with invalid arity %d, expected 1",
				callback.method_name,
				arity,
			)
			panic("EXITING")
		}

		if callback.has_flag != nil {
			callback.has_flag^ = true
		}
	}
}

call_user_events :: proc() {
	if g.mrb_state == nil { return }
	event_queue := mrb.gv_get(g.mrb_state, mrb.intern_cstr(g.mrb_state, "$event_queue"))
	dispatch_funcall(event_queue, "process_events", 0, nil, .EVENT)
}

call_user_update :: proc() {
	if g.mrb_state == nil || !g.has_update { return }
	dispatch_funcall(mrb.top_self(g.mrb_state), "update", 0, nil, .UPDATE)
}

call_user_draw :: proc() {
	if g.clear_color.a != 0 { rl.ClearBackground(g.clear_color) }
	if g.mrb_state == nil || !g.has_draw { return }
	dispatch_funcall(mrb.top_self(g.mrb_state), "draw", 0, nil, .DRAW)
}

call_user_ui :: proc() {
	if g.mrb_state == nil || !g.has_ui { return }
	dispatch_funcall(mrb.top_self(g.mrb_state), "ui", 0, nil, .UI)
}
