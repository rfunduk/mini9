package engine

import "core:log"
import "core:slice"
import mrb "lib:mruby"
import rl "vendor:raylib"

// callback info for checking method existence and arity
Callback_Info :: struct {
	method_name:   cstring,
	valid_arities: [2]i32,
	has_flag:      ^bool,
	wants_param:   ^bool, // optional - nil if method doesn't take parameters
}

// check Ruby function arities using native mruby introspection
determine_game_callbacks :: proc() {
	if g.mrb_state == nil { return }

	callback_infos := [?]Callback_Info {
		{"event", {1, -1}, &g.has_event, nil},
		{"update", {0, 1}, &g.has_update, &g.wants_dt},
		{"draw", {0, -1}, &g.has_draw, nil},
		{"ui", {0, -1}, &g.has_ui, nil},
	}

	top := mrb.top_self(g.mrb_state)

	for &callback in callback_infos {
		sym := mrb.intern_cstr(g.mrb_state, callback.method_name)

		if !mrb.respond_to(g.mrb_state, top, sym) {
			continue
		}

		arity := i32(mrb.method_arity(g.mrb_state, top, sym))

		// -2 = undefined, -1 = C func (variable args)
		if arity <= -1 {
			callback.has_flag^ = false
			continue
		}

		if !slice.contains(callback.valid_arities[:], arity) {
			log.errorf(
				"[ENGINE] ERROR: Callback `%s` defined with invalid arity %d, expected %v",
				callback.method_name,
				arity,
				callback.valid_arities[:],
			)
			panic("EXITING")
		} else {
			if arity == 0 {
				callback.has_flag^ = true
			} else if arity == 1 {
				callback.has_flag^ = true
				if callback.wants_param != nil {
					callback.wants_param^ = true
				}
			}
		}
	}
}

call_user_events :: proc() {
	if g.mrb_state == nil { return }
	event_queue := mrb.gv_get(g.mrb_state, mrb.intern_cstr(g.mrb_state, "$event_queue"))
	dispatch_funcall(event_queue, "process_events", 0, nil, .EVENT)
}

call_user_update :: proc(dt: f32) {
	if g.mrb_state == nil || !g.has_update { return }

	if g.has_update && g.wants_dt {
		dt_value := mrb.word_boxing_float_value(g.mrb_state, f64(dt))
		argv := ([^]mrb.Value)(&dt_value)
		dispatch_funcall(mrb.top_self(g.mrb_state), "update", 1, argv, .UPDATE)
	} else if g.has_update {
		dispatch_funcall(mrb.top_self(g.mrb_state), "update", 0, nil, .UPDATE)
	}
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
