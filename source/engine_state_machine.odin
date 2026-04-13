package engine

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

get_proc_arity :: proc(proc_val: mrb.Value) -> i32 {
	if proc_val == mrb.NIL { return 0 }
	return i32(mrb.proc_arity(proc_val))
}

// RUBY FUNCTION: state(:name, enter: nil, exit: nil, update: nil) -> returns State object
// @engine_method: name="state", arity=-1
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
		enter_arity  = get_proc_arity(enter_proc),
		update_arity = get_proc_arity(update_proc),
		exit_arity   = get_proc_arity(exit_proc),
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
// @engine_method: name="fsm", arity=1
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

// FSM.init(this_obj) - set the object that callbacks receive as first arg
ruby_fsm_init :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
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
			switch current.exit_arity {
			case 0:
				mrb.funcall(state, current.exit_proc, "call", 0)
			case 1:
				mrb.funcall(state, current.exit_proc, "call", 1, fsm.this_obj)
			case 2:
				mrb.funcall(state, current.exit_proc, "call", 2, fsm.this_obj, fsm.current_state)
			case 3:
				mrb.funcall(state, current.exit_proc, "call", 3, fsm.this_obj, fsm.current_state, next_state)
			}
		}
	}

	last_state := fsm.current_state
	fsm.current_state = next_state

	// Call enter on new state
	next := extract_native(State, next_state)
	if next != nil && next.enter_proc != mrb.NIL {
		switch next.enter_arity {
		case 0:
			mrb.funcall(state, next.enter_proc, "call", 0)
		case 1:
			mrb.funcall(state, next.enter_proc, "call", 1, fsm.this_obj)
		case 2:
			mrb.funcall(state, next.enter_proc, "call", 2, fsm.this_obj, next_state)
		case 3:
			mrb.funcall(state, next.enter_proc, "call", 3, fsm.this_obj, next_state, last_state)
		}
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

// FSM.update(dt) - the hot path we're optimizing
ruby_fsm_update :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	dt_val: mrb.Value
	mrb.get_args(state, "o", &dt_val)

	fsm := extract_native(FSM, self)
	if fsm == nil { return mrb.NIL }

	// Auto-transition to default on first update
	if fsm.current_state == mrb.NIL { do_fsm_transition(state, fsm, fsm.default_name) }

	current := extract_native(State, fsm.current_state)
	if current == nil { return mrb.NIL }

	if current.update_proc != mrb.NIL {
		switch current.update_arity {
		case 0:
			mrb.funcall(state, current.update_proc, "call", 0)
		case 1:
			mrb.funcall(state, current.update_proc, "call", 1, fsm.this_obj)
		case 2:
			mrb.funcall(state, current.update_proc, "call", 2, fsm.this_obj, fsm.current_state)
		case 3:
			mrb.funcall(state, current.update_proc, "call", 3, fsm.this_obj, fsm.current_state, dt_val)
		}
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
	mrb.define_method(g.mrb_state, sc, "name", cast(rawptr)ruby_state_name, 0)
	mrb.define_method(g.mrb_state, sc, "data", cast(rawptr)ruby_state_data, 0)
	mrb.define_method(g.mrb_state, sc, "fsm", cast(rawptr)ruby_state_fsm, 0)
	mrb.define_method(g.mrb_state, sc, "transition", cast(rawptr)ruby_state_transition, 1)

	// Setup FSM class
	fc := mrb.get_data_class(g.mrb_state, "FSM")
	mrb.define_method(g.mrb_state, fc, "init", cast(rawptr)ruby_fsm_init, 1)
	mrb.define_method(g.mrb_state, fc, "update", cast(rawptr)ruby_fsm_update, 1)
	mrb.define_method(g.mrb_state, fc, "transition", cast(rawptr)ruby_fsm_transition, 1)
	mrb.define_method(g.mrb_state, fc, "state", cast(rawptr)ruby_fsm_state, 0)
}
