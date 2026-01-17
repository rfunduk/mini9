package engine

import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

// callback info for checking method existence and arity
Callback_Info :: struct {
	method_name:   string,
	valid_arities: [2]i32,
	has_flag:      ^bool,
	wants_param:   ^bool, // optional - nil if method doesn't take parameters
}

// check Ruby function arities using Ruby's method introspection
determine_game_callbacks :: proc() {
	if g.mrb_state == nil { return }

	callback_infos := [?]Callback_Info {
		{"event", {1, -1}, &g.has_event, nil},
		{"update", {0, 1}, &g.has_update, &g.wants_dt},
		{"draw", {0, -1}, &g.has_draw, nil},
		{"ui", {0, -1}, &g.has_ui, nil},
	}

	for &callback in callback_infos {
		method_cstr := strings.clone_to_cstring(callback.method_name)
		defer delete(method_cstr)

		if !ruby_function_exists(method_cstr) {
			// log.debugf("No `%s` callback defined", callback.method_name)
			continue
		}
		// log.debugf("Found `%s` callback", callback.method_name)

		arity_query := fmt.aprintf(
			"respond_to?(:%s) ? method(:%s).arity : -1",
			callback.method_name,
			callback.method_name,
		)
		defer delete(arity_query)

		arity_result := mrb.load_string(g.mrb_state, strings.clone_to_cstring(arity_query))

		if has_ruby_exception(g.mrb_state) {
			log.warnf("Unable to confirm existence of `%s` callback", callback.method_name)
		}

		arity := mrb.integer_p(arity_result) ? mrb.integer(arity_result) : -1

		if arity == -1 {
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
			os.exit(1)
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
