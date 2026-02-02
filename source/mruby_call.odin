package engine

import "core:c"
import mrb "lib:mruby"

Ruby_Call_Context :: enum {
	UNKNOWN,
	INIT,
	UPDATE,
	DRAW,
	UI,
	EVENT,
	TWEEN_CALLBACK,
}

// protected call data structures
Funcall_Data :: struct {
	obj:    mrb.Value,
	method: cstring,
	argc:   c.int,
	argv:   [^]mrb.Value,
}

Yield_Data :: struct {
	block: mrb.Value,
	arg:   mrb.Value,
}

Load_Data :: struct {
	code: cstring,
}

Protected_Call_Data :: struct {
	ctx:     Ruby_Call_Context,
	variant: union {
		Funcall_Data,
		Yield_Data,
		Load_Data,
	},
}

// universal protected dispatch function
protected_dispatch :: proc "c" (state: mrb.State, data: mrb.Value) -> mrb.Value {
	context = global_context
	call_data := cast(^Protected_Call_Data)mrb.ptr(data)

	switch v in call_data.variant {
	case Funcall_Data:
		_ = mrb.funcall_argv(state, v.obj, mrb.intern_cstr(state, v.method), v.argc, v.argv)
	case Yield_Data:
		_ = mrb.yield(state, v.block, v.arg)
	case Load_Data:
		_ = mrb.load_string_cxt(state, v.code, g.mrb_ctx)
	}
	return mrb.NIL
}

// conditional dispatch - safe in debug, fast in release
dispatch_funcall :: proc(
	obj: mrb.Value,
	method: cstring,
	argc: c.int = 0,
	argv: [^]mrb.Value = nil,
	ctx: Ruby_Call_Context = .UNKNOWN,
) -> bool {
	// always protect tween callbacks since they can't crash the whole system
	if ctx == .TWEEN_CALLBACK {
		return protected_funcall(obj, method, argc, argv, ctx)
	}

	when #config(SAFE_DISPATCH, false) {
		return protected_funcall(obj, method, argc, argv, ctx)
	} else {
		// save arena to prevent funcall memory leaks
		arena_idx := mrb.gc_arena_save(g.mrb_state)
		defer mrb.gc_arena_restore(g.mrb_state, arena_idx)

		_ = mrb.funcall_argv(g.mrb_state, obj, mrb.intern_cstr(g.mrb_state, method), argc, argv)

		// for regular user code, still check and print exceptions but don't use mrb_protect
		// this gives us the old behavior: print backtrace but let execution continue
		if has_ruby_exception(g.mrb_state) {
			// get the exception from mrb->exc directly
			offset: uintptr = 32 // mrb->exc offset on 64-bit
			when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 { offset = 16 }
			exc_ptr := cast(^rawptr)(uintptr(g.mrb_state) + offset)
			exc := mrb.Value {
				w = uintptr(exc_ptr^),
			}

			handle_ruby_exception(exc, ctx)
		}

		return true
	}
}

// high-level protected wrapper functions
protected_funcall :: proc(
	obj: mrb.Value,
	method: cstring,
	argc: c.int = 0,
	argv: [^]mrb.Value = nil,
	ctx: Ruby_Call_Context = .UNKNOWN,
) -> bool {
	call_data := Protected_Call_Data {
		ctx = ctx,
		variant = Funcall_Data{obj = obj, method = method, argc = argc, argv = argv},
	}

	data_ptr := rawptr(&call_data)
	data_value := mrb.Value {
		w = uintptr(data_ptr),
	}

	exception_occurred: c.bool = false
	exc_result := mrb.protect(g.mrb_state, protected_dispatch, data_value, &exception_occurred)

	if exception_occurred {
		handle_ruby_exception(exc_result, ctx)
		return false
	}

	return true
}

protected_yield :: proc(block: mrb.Value, arg: mrb.Value, ctx: Ruby_Call_Context = .TWEEN_CALLBACK) -> bool {
	call_data := Protected_Call_Data {
		ctx = ctx,
		variant = Yield_Data{block = block, arg = arg},
	}

	data_ptr := rawptr(&call_data)
	data_value := mrb.Value {
		w = uintptr(data_ptr),
	}

	exception_occurred: c.bool = false
	exc_result := mrb.protect(g.mrb_state, protected_dispatch, data_value, &exception_occurred)

	if exception_occurred {
		handle_ruby_exception(exc_result, ctx)
		return false
	}

	return true
}
