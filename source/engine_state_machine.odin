package engine

import "core:c"
import "core:fmt"
import "core:log"
import mrb "lib:mruby"

// States are pure-Ruby GameObjects (see ruby_api/state_machine.rb) — the
// native side only holds the graph and dispatches by handler name. Handler
// procs live in the state's @_procs table, which hot reload swaps, so
// dispatch here always runs fresh code with no proc juggling.
FSM :: struct {
	parent:        mrb.Value,
	current_state: mrb.Value, // Current State ruby object
	default_name:  mrb.Value, // Symbol
	states:        mrb.Value, // Array of State objects (linear search - most FSMs have 2-5 states)
}

// Protected call of an FSM enter/exit/update block. `arity` trims argv (or
// pass all 3 for variadic / arity > 3). `ctx_msg` is logged before the
// exception handler on raise so the user sees which transition blew up.
@(private)
dispatch_fsm_callback :: proc(block: mrb.Value, arity: i32, argv: []mrb.Value, ctx_msg: string) -> bool {
	effective := arity
	if effective < 0 || effective > i32(len(argv)) { effective = i32(len(argv)) }
	ok, exc := mrb.protected_funcall(g.mrb_state, block, "call", c.int(effective), raw_data(argv))
	if !ok {
		log.errorf("[FSM] %s raised:", ctx_msg)
		handle_ruby_exception(g.mrb_state, exc, .FSM_CALLBACK)
	}
	return ok
}

// Fetch the `kind` handler (:enter/:update/:draw/:exit) from a State's proc
// table and protected-call it. A missing handler is a silent skip.
@(private)
dispatch_state_handler :: proc(state_obj: mrb.Value, kind: mrb.Value, argv: []mrb.Value, ctx_msg: string) -> bool {
	args := [1]mrb.Value{kind}
	handler := mrb.funcall_argv(
		g.mrb_state,
		state_obj,
		mrb.symbol(sym._handler_for),
		1,
		raw_data(args[:]),
	)
	if handler == mrb.NIL { return true }
	return dispatch_fsm_callback(handler, mrb.safe_proc_arity(handler), argv, ctx_msg)
}

// Raise ArgumentError if `kwargs` contains any key not in `allowed`.
// Must be called with no active Odin defers (raise longjmps past them)
@(private)
reject_unknown_kwargs :: proc(state: mrb.State, kwargs: mrb.Value, fn_name: string, allowed: []mrb.Value) {
	if kwargs == mrb.NIL || !mrb.hash_p(kwargs) { return }
	keys := mrb.hash_keys(state, kwargs)
	for i in 0 ..< mrb.ary_len(keys) {
		key := mrb.ary_entry(keys, i32(i))
		known := false
		for a in allowed { if key.w == a.w { known = true; break } }
		if !known {
			mrb.raise_error(
				state,
				"ArgumentError",
				"%s: unknown keyword %s",
				fn_name,
				mrb.inspect(state, key, context.temp_allocator),
			)
		}
	}
}

// FSM requires a GameObject owner.
// Must be called with no active Odin defers (raise longjmps past them)
@(private)
fsm_require_owner :: proc(state: mrb.State, fsm: ^FSM) {
	if fsm.parent == mrb.NIL {
		mrb.raise_error(
			state,
			"RuntimeError",
			"FSM has no current state — an FSM must be a field on a game object: obj(fsm: fsm(default: ...))",
		)
	}
}

ruby_fsm_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		f := cast(^FSM)ptr
		if f.states != mrb.NIL { mrb.gc_unregister(state, f.states) }
		mrb.free(state, ptr)
	}
}

// RUBY FUNCTION: fsm(default:, states:) -> returns FSM object
// @engine_method: name="fsm", aspec=ARGS_REQ(1)
ruby_fsm :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "H", &kwargs)

	reject_unknown_kwargs(state, kwargs, "fsm", {sym.default, sym.states})

	default_name := mrb.kwarg(state, kwargs, sym.default)
	states_array := mrb.kwarg(state, kwargs, sym.states)

	if default_name == mrb.NIL {
		mrb.raise_error(state, "ArgumentError", "fsm: missing required keyword :default")
	}

	if states_array == mrb.NIL { states_array = mrb.ary_new(state) }
	if !mrb.array_p(states_array) {
		mrb.raise_error(state, "ArgumentError", "fsm: states: must be an Array of state(...) objects")
	}

	// Validate element types before allocating (raise longjmps).
	set_fsm := mrb.intern_cstr(state, "_set_fsm")
	length := mrb.ary_len(states_array)
	for i in 0 ..< length {
		state_val := mrb.ary_entry(states_array, i32(i))
		if !mrb.respond_to(state, state_val, set_fsm) {
			mrb.raise_error(state, "ArgumentError", "fsm: states: must be an Array of state(...) objects")
		}
	}

	f := FSM {
		parent        = mrb.NIL,
		current_state = mrb.NIL,
		default_name  = default_name,
		states        = states_array,
	}
	fsm_ptr := mrb.alloc(g.mrb_state, f)

	// GC register after allocation since we now have a ref
	mrb.gc_register(state, states_array)

	fsm_class := mrb.class_get(state, "FSM")
	ruby_obj := mrb.obj_new(state, fsm_class, 0, nil)
	mrb.data_init(ruby_obj, fsm_ptr, NATIVE_TO_MRUBY_TYPE[FSM])

	// Set FSM reference on each state
	for i in 0 ..< length {
		state_val := mrb.ary_entry(states_array, i32(i))
		args := [1]mrb.Value{ruby_obj}
		mrb.funcall_argv(state, state_val, set_fsm, 1, raw_data(args[:]))
	}

	return ruby_obj
}

// FSM._on_attach(parent) - set the parent object
ruby_fsm_on_attach :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	parent_val: mrb.Value
	mrb.get_args(state, "o", &parent_val)

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }
	fsm.parent = parent_val

	// Enter the default state now that `parent` is wired
	if fsm.current_state == mrb.NIL && fsm.default_name != mrb.NIL {
		do_fsm_transition(state, fsm, fsm.default_name)
	}

	return self
}

@(private)
state_name :: proc(state: mrb.State, state_obj: mrb.Value) -> mrb.Value {
	return mrb.funcall_argv(state, state_obj, mrb.symbol(sym.name), 0, nil)
}

find_state_by_name :: proc(state: mrb.State, states_array: mrb.Value, name: mrb.Value) -> mrb.Value {
	length := mrb.ary_len(states_array)

	for i in 0 ..< length {
		state_val := mrb.ary_entry(states_array, i32(i))
		if state_name(state, state_val).w == name.w { return state_val }
	}
	return mrb.NIL
}

do_fsm_transition :: proc(state: mrb.State, fsm: ^FSM, next_name: mrb.Value) {
	next_state := find_state_by_name(state, fsm.states, next_name)
	if next_state == mrb.NIL {
		// Get state name as string for error message
		name_str := mrb.funcall(state, next_name, "inspect", 0)
		name_cstr := mrb.string_cstr(state, name_str)
		runtime_error := mrb.exc_get_id(state, mrb.intern_cstr(state, "RuntimeError"))
		mrb.raisef(state, runtime_error, "FSM transition to unknown state: %s", name_cstr)
		return
	}

	// Don't transition to same state
	if next_state.w == fsm.current_state.w { return }

	// Call exit on current state
	if fsm.current_state != mrb.NIL {
		current := state_name(state, fsm.current_state)
		argv := [3]mrb.Value{fsm.parent, fsm.current_state, next_state}
		msg := fmt.tprintf(
			"%s exit -> %s",
			mrb.inspect(state, current, context.temp_allocator),
			mrb.inspect(state, next_name, context.temp_allocator),
		)
		dispatch_state_handler(fsm.current_state, sym.exit, argv[:], msg)
	}

	last_state := fsm.current_state
	fsm.current_state = next_state

	// Call enter on new state
	{
		current := state_name(state, next_state)
		from_name := "nil"
		if last_state != mrb.NIL {
			from_name = mrb.inspect(state, state_name(state, last_state), context.temp_allocator)
		}
		argv := [3]mrb.Value{fsm.parent, next_state, last_state}
		msg := fmt.tprintf(
			"%s -> %s enter",
			from_name,
			mrb.inspect(state, current, context.temp_allocator),
		)
		dispatch_state_handler(next_state, sym.enter, argv[:], msg)
	}
}

// FSM.transition(:state_name)
ruby_fsm_transition :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	state_name: mrb.Value
	mrb.get_args(state, "o", &state_name)

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	fsm_require_owner(state, fsm)
	do_fsm_transition(state, fsm, state_name)
	return mrb.NIL
}

ruby_fsm_update :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	fsm_require_owner(state, fsm)
	if fsm.current_state == mrb.NIL { return mrb.NIL }

	current := state_name(state, fsm.current_state)
	argv := [2]mrb.Value{fsm.parent, fsm.current_state}
	msg := fmt.tprintf("%s update", mrb.inspect(state, current, context.temp_allocator))
	dispatch_state_handler(fsm.current_state, sym.update, argv[:], msg)

	return mrb.NIL
}

ruby_fsm_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	fsm_require_owner(state, fsm)
	if fsm.current_state == mrb.NIL { return mrb.NIL }

	current := state_name(state, fsm.current_state)
	argv := [2]mrb.Value{fsm.parent, fsm.current_state}
	msg := fmt.tprintf("%s draw", mrb.inspect(state, current, context.temp_allocator))
	dispatch_state_handler(fsm.current_state, sym.draw, argv[:], msg)

	return mrb.NIL
}

// FSM.state - get current state
ruby_fsm_state :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }
	return fsm.current_state
}

// FSM._reload_merge!(fresh) — hot-reload structural sync. Behavior needs no
// handling here (states are Ruby objects whose proc tables the GameObject
// merge swaps); this reconciles the graph: states matched by name keep
// identity and merge, new ones are adopted, default carries over. Current
// state is re-pinned by name and may dangle detached if renamed away
// (self-heals on the next transition). enter/exit do NOT refire.
ruby_fsm_reload_merge :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	fresh_val: mrb.Value
	mrb.get_args(state, "o", &fresh_val)

	old_fsm := extract_native(FSM, self)
	new_fsm := extract_native(FSM, fresh_val)
	if old_fsm == nil || new_fsm == nil { return mrb.NIL }

	name_sym := mrb.intern_cstr(state, "name")
	set_fsm_sym := mrb.intern_cstr(state, "_set_fsm")
	merge_sym := mrb.intern_cstr(state, "_reload_merge!")

	merged := mrb.ary_new(state)
	mrb.gc_register(state, merged)

	new_len := mrb.ary_len(new_fsm.states)
	for i in 0 ..< new_len {
		fresh_state := mrb.ary_entry(new_fsm.states, i32(i))
		fresh_name := mrb.funcall_argv(state, fresh_state, name_sym, 0, nil)
		survivor := find_state_by_name(state, old_fsm.states, fresh_name)
		if survivor != mrb.NIL {
			args := [1]mrb.Value{fresh_state}
			mrb.funcall_argv(state, survivor, merge_sym, 1, raw_data(args[:]))
			mrb.ary_push(state, merged, survivor)
		} else {
			args := [1]mrb.Value{self}
			mrb.funcall_argv(state, fresh_state, set_fsm_sym, 1, raw_data(args[:]))
			mrb.ary_push(state, merged, fresh_state)
		}
	}

	if old_fsm.states != mrb.NIL { mrb.gc_unregister(state, old_fsm.states) }
	old_fsm.states = merged
	old_fsm.default_name = new_fsm.default_name

	// Re-pin current by name; a renamed-away current dangles detached.
	if old_fsm.current_state != mrb.NIL {
		current_name := mrb.funcall_argv(state, old_fsm.current_state, name_sym, 0, nil)
		repinned := find_state_by_name(state, merged, current_name)
		if repinned != mrb.NIL {
			old_fsm.current_state = repinned
		} else {
			log.warnf(
				"[hot-reload] FSM current state %s removed by reload; keeping it until the next transition",
				mrb.inspect(state, current_name, context.temp_allocator),
			)
		}
	}

	return self
}

setup_state_machine :: proc() {
	// Setup FSM class
	fc := mrb.get_data_class(g.mrb_state, "FSM")
	mrb.define_method(g.mrb_state, fc, "_on_attach", cast(rawptr)ruby_fsm_on_attach, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, fc, "update", cast(rawptr)ruby_fsm_update, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, fc, "draw", cast(rawptr)ruby_fsm_draw, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, fc, "transition", cast(rawptr)ruby_fsm_transition, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, fc, "state", cast(rawptr)ruby_fsm_state, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, fc, "_reload_merge!", cast(rawptr)ruby_fsm_reload_merge, mrb.ARGS_REQ(1))
}
