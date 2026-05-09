package engine

import "core:c"
import "core:fmt"
import "core:log"
import mrb "lib:mruby"

State :: struct {
	name:         mrb.Value, // Symbol
	data:         mrb.Value, // obj() for user data
	fsm:          mrb.Value, // Parent FSM reference
	enter_proc:   mrb.Value,
	update_proc:  mrb.Value,
	exit_proc:    mrb.Value,
	enter_arity:  i32,
	update_arity: i32,
	exit_arity:   i32,
}

FSM :: struct {
	this_obj:      mrb.Value, // GC registered
	current_state: mrb.Value, // Current State ruby object
	default_name:  mrb.Value, // Symbol
	states:        mrb.Value, // Array of State objects (linear search - most FSMs have 2-5 states)
}

// Protected call of an FSM enter/exit/update block. `arity` is the cached
// proc arity from the State struct — trim argv to match (or pass all 3 for
// variadic / arity > 3). `ctx_msg` is logged before the exception handler
// on raise so the user sees which transition blew up.
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

ruby_state_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		s := cast(^State)ptr
		// unregister GC-registered values
		if s.data != mrb.NIL { mrb.gc_unregister(state, s.data) }
		if s.enter_proc != mrb.NIL { mrb.gc_unregister(state, s.enter_proc) }
		if s.update_proc != mrb.NIL { mrb.gc_unregister(state, s.update_proc) }
		if s.exit_proc != mrb.NIL { mrb.gc_unregister(state, s.exit_proc) }
		mrb.free(state, ptr)
	}
}

ruby_fsm_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		f := cast(^FSM)ptr
		if f.this_obj != mrb.NIL { mrb.gc_unregister(state, f.this_obj) }
		if f.states != mrb.NIL { mrb.gc_unregister(state, f.states) }
		mrb.free(state, ptr)
	}
}

// RUBY FUNCTION: state(:name, enter: nil, exit: nil, update: nil) -> returns State object
// @engine_method: name="state", aspec=ARGS_ARG(1,1)
ruby_state :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	name_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &name_val, &kwargs)

	enter_proc := mrb.NIL
	exit_proc := mrb.NIL
	update_proc := mrb.NIL

	if argc >= 2 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.enter)
		if val != mrb.NIL { enter_proc = val }
		val = mrb.kwarg(state, kwargs, sym.exit)
		if val != mrb.NIL { exit_proc = val }
		val = mrb.kwarg(state, kwargs, sym.update)
		if val != mrb.NIL { update_proc = val }
	}

	// Create the data obj for state-specific data
	pos := create_vector2({0, 0})
	obj_scale := create_vector2({1, 1})
	mrb.gc_register(state, pos)
	mrb.gc_register(state, obj_scale)
	data_obj := create_game_object(Game_Object{pos = pos, scale = obj_scale, visible = true}, 0, nil)

	s := State {
		name         = name_val,
		data         = data_obj,
		fsm          = mrb.NIL, // will be set when added to FSM
		enter_proc   = enter_proc,
		update_proc  = update_proc,
		exit_proc    = exit_proc,
		enter_arity  = mrb.safe_proc_arity(enter_proc),
		update_arity = mrb.safe_proc_arity(update_proc),
		exit_arity   = mrb.safe_proc_arity(exit_proc),
	}
	state_ptr := mrb.alloc(g.mrb_state, s)

	// GC register the procs and data
	if data_obj != mrb.NIL { mrb.gc_register(state, data_obj) }
	if enter_proc != mrb.NIL { mrb.gc_register(state, enter_proc) }
	if update_proc != mrb.NIL { mrb.gc_register(state, update_proc) }
	if exit_proc != mrb.NIL { mrb.gc_register(state, exit_proc) }

	state_class := mrb.class_get(state, "State")
	ruby_obj := mrb.obj_new(state, state_class, 0, nil)
	mrb.data_init(ruby_obj, state_ptr, NATIVE_TO_MRUBY_TYPE[State])

	return ruby_obj
}

// RUBY FUNCTION: fsm(default:, states:) -> returns FSM object
// @engine_method: name="fsm", aspec=ARGS_REQ(1)
ruby_fsm :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "H", &kwargs)

	default_name := mrb.kwarg(state, kwargs, sym.default)
	states_array := mrb.kwarg(state, kwargs, sym.states)

	if states_array == mrb.NIL { states_array = mrb.ary_new(state) }

	f := FSM {
		this_obj      = mrb.NIL,
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

	// Set FSM reference on each state (only if array is valid)
	if states_array != mrb.NIL && mrb.array_p(states_array) {
		// Get array length - handles both embedded and heap arrays
		length := mrb.ary_len(states_array)

		for i in 0 ..< length {
			state_val := mrb.ary_entry(states_array, i32(i))
			state_native := extract_native(State, state_val)
			if state_native != nil { state_native.fsm = ruby_obj }
		}
	}

	return ruby_obj
}

// FSM._attach(this_obj) - set the object that callbacks receive as first arg
ruby_fsm_attach :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	this_obj: mrb.Value
	mrb.get_args(state, "o", &this_obj)

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	// Unregister old this_obj if any
	if fsm.this_obj != mrb.NIL { mrb.gc_unregister(state, fsm.this_obj) }

	fsm.this_obj = this_obj
	if this_obj != mrb.NIL { mrb.gc_register(state, this_obj) }

	return self
}

find_state_by_name :: proc(state: mrb.State, states_array: mrb.Value, name: mrb.Value) -> mrb.Value {
	length := mrb.ary_len(states_array)

	for i in 0 ..< length {
		state_val := mrb.ary_entry(states_array, i32(i))
		state_native := extract_native(State, state_val)
		if state_native == nil { continue }
		if state_native.name.w == name.w { return state_val }
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
		current := extract_native(State, fsm.current_state)
		if current != nil && current.exit_proc != mrb.NIL {
			argv := [3]mrb.Value{fsm.this_obj, fsm.current_state, next_state}
			msg := fmt.tprintf(
				"%s exit -> %s",
				mrb.inspect(state, current.name, context.temp_allocator),
				mrb.inspect(state, next_name, context.temp_allocator),
			)
			dispatch_fsm_callback(current.exit_proc, current.exit_arity, argv[:], msg)
		}
	}

	last_state := fsm.current_state
	fsm.current_state = next_state

	// Call enter on new state
	next := extract_native(State, next_state)
	if next != nil && next.enter_proc != mrb.NIL {
		argv := [3]mrb.Value{fsm.this_obj, next_state, last_state}
		from_name :=
			last_state == mrb.NIL ? "nil" : mrb.inspect(state, extract_native(State, last_state).name, context.temp_allocator)
		msg := fmt.tprintf(
			"%s -> %s enter",
			from_name,
			mrb.inspect(state, next.name, context.temp_allocator),
		)
		dispatch_fsm_callback(next.enter_proc, next.enter_arity, argv[:], msg)
	}
}

// FSM.transition(:state_name)
ruby_fsm_transition :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	state_name: mrb.Value
	mrb.get_args(state, "o", &state_name)

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	do_fsm_transition(state, fsm, state_name)
	return mrb.NIL
}

ruby_fsm_update :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	// Auto-transition to default on first update
	if fsm.current_state == mrb.NIL { do_fsm_transition(state, fsm, fsm.default_name) }

	current := extract_native(State, fsm.current_state)
	if current == nil { return mrb.NIL }

	if current.update_proc != mrb.NIL {
		argv := [2]mrb.Value{fsm.this_obj, fsm.current_state}
		msg := fmt.tprintf("%s update", mrb.inspect(state, current.name, context.temp_allocator))
		dispatch_fsm_callback(current.update_proc, current.update_arity, argv[:], msg)
	}

	return mrb.NIL
}

// FSM.state - get current state
ruby_fsm_state :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }
	return fsm.current_state
}

// State.name
ruby_state_name :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	s := extract_native(State, self)
	if s == nil { return mrb.NIL }
	return s.name
}

// State.data
ruby_state_data :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	s := extract_native(State, self)
	if s == nil { return mrb.NIL }
	return s.data
}

// State.fsm
ruby_state_fsm :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	s := extract_native(State, self)
	if s == nil { return mrb.NIL }
	return s.fsm
}

// State.transition(:name) - convenience for state.fsm.transition(:name)
ruby_state_transition :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	state_name: mrb.Value
	mrb.get_args(state, "o", &state_name)

	s := extract_native(State, self)
	if s == nil || s.fsm == mrb.NIL { return mrb.NIL }

	fsm := extract_native(FSM, s.fsm)
	if fsm == nil { return mrb.NIL }

	do_fsm_transition(state, fsm, state_name)
	return mrb.NIL
}

setup_state_machine :: proc() {
	// Setup State class
	sc := mrb.get_data_class(g.mrb_state, "State")
	mrb.define_method(g.mrb_state, sc, "name", cast(rawptr)ruby_state_name, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, sc, "data", cast(rawptr)ruby_state_data, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, sc, "fsm", cast(rawptr)ruby_state_fsm, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, sc, "transition", cast(rawptr)ruby_state_transition, mrb.ARGS_REQ(1))

	// Setup FSM class
	fc := mrb.get_data_class(g.mrb_state, "FSM")
	mrb.define_method(g.mrb_state, fc, "_attach", cast(rawptr)ruby_fsm_attach, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, fc, "update", cast(rawptr)ruby_fsm_update, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, fc, "transition", cast(rawptr)ruby_fsm_transition, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, fc, "state", cast(rawptr)ruby_fsm_state, mrb.ARGS_NONE)
}
