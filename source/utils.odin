package engine

import "core:c"
import "core:log"
import "core:strings"
import mrb "lib:mruby"


@(require_results)
read_entire_file :: proc(
	name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: []byte,
	success: bool,
) {
	return _read_entire_file(name, allocator, loc)
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return _write_entire_file(name, data, truncate)
}

file_exists :: proc(name: string) -> bool {
	return _file_exists(name)
}

resolve_log_level :: proc(flag: string) -> (level: log.Level, ok: bool) {
	default_level: log.Level = .Warning when !ENGINE_DEBUG else .Debug
	
	// odinfmt:disable
	switch strings.to_lower(flag, context.temp_allocator) {
	case "":                return default_level, true
	case "debug":           return .Debug, true
	case "info":            return .Info, true
	case "warn", "warning": return .Warning, true
	case "error":           return .Error, true
	case "fatal":           return .Fatal, true
	}
	// odinfmt:enable

	return default_level, false
}

extract_native :: #force_inline proc($T: typeid, val: mrb.Value) -> ^T {
	when #config(CHECK_MRUBY_DATA_TYPES, false) {
		return cast(^T)mrb.data_check_get_ptr(g.mrb_state, val, NATIVE_TO_MRUBY_TYPE[T])
	} else {
		return cast(^T)mrb.data_get_ptr(g.mrb_state, val, NATIVE_TO_MRUBY_TYPE[T])
	}
}

// Type-sniff a Ruby value: true iff `val` is a native data object of type T.
// Always uses the safe, no-raise check (independent of CHECK_MRUBY_DATA_TYPES)
// because the only point of calling this is to *branch* on the type — e.g. a
// shape-argument that accepts either a Rect or a Circ. Use it to discriminate,
// then call `extract_native` once you know which form it is.
is_native :: #force_inline proc($T: typeid, val: mrb.Value) -> bool {
	return mrb.data_check_get_ptr(g.mrb_state, val, NATIVE_TO_MRUBY_TYPE[T]) != nil
}


// Engine-side label for which callback path was running when an exception
// fired. The lib's protect helpers don't know about this — it lives here so
// `handle_ruby_exception` can tell the user "error in UPDATE" vs "in DRAW",
// which is useful when the failing function is something generic like a state
// machine handler whose backtrace doesn't make the dispatch context obvious.
Ruby_Call_Context :: enum {
	UNKNOWN,
	INIT,
	UPDATE,
	DRAW,
	UI,
	EVENT,
	TWEEN_CALLBACK,
	TIMER_CALLBACK,
	FSM_CALLBACK,
	SENSOR_EVENT,
}

// Top-level Ruby callback dispatch with engine policy applied:
//   - tween callbacks always run inside mrb_protect (a raise inside flux'
//     internal iteration must not crash the VM)
//   - debug builds (SAFE_DISPATCH) run everything through mrb_protect so
//     exceptions can be surfaced via the error overlay
//   - release builds run the fast path: a single funcall with arena
//     save/restore, then a post-call has_exception check
//
// In all cases, an exception is routed through `handle_ruby_exception` with
// the originating ctx so the user sees which phase blew up.
dispatch_funcall :: proc(
	obj: mrb.Value,
	method: cstring,
	argc: c.int = 0,
	argv: [^]mrb.Value = nil,
	ctx: Ruby_Call_Context = .UNKNOWN,
) -> bool {
	if ctx == .TWEEN_CALLBACK {
		return _protected(obj, method, argc, argv, ctx)
	}

	when #config(SAFE_DISPATCH, false) {
		return _protected(obj, method, argc, argv, ctx)
	} else {
		mrb.funcall_safe(g.mrb_state, obj, method, argc, argv)
		if mrb.has_exception(g.mrb_state) {
			handle_ruby_exception(g.mrb_state, mrb.current_exception(g.mrb_state), ctx)
		}
		return true
	}
}

// Yield to a block under mrb_protect, routing any exception through the
// engine's error handler. Always protected — callers run in contexts where
// a raise would otherwise corrupt VM state (e.g. tween inside flux iteration)
// or where local recovery beats unwinding to the outer protect frame.
dispatch_yield :: proc(block: mrb.Value, arg: mrb.Value, ctx: Ruby_Call_Context) -> bool {
	ok, exc := mrb.protected_yield(g.mrb_state, block, arg)
	if !ok { handle_ruby_exception(g.mrb_state, exc, ctx) }
	return ok
}

@(private)
_protected :: proc(
	obj: mrb.Value,
	method: cstring,
	argc: c.int,
	argv: [^]mrb.Value,
	ctx: Ruby_Call_Context,
) -> bool {
	ok, exc := mrb.protected_funcall(g.mrb_state, obj, method, argc, argv)
	if !ok { handle_ruby_exception(g.mrb_state, exc, ctx) }
	return ok
}

// Engine-side wrapper around `mrb.load_bytecode` for loading the precompiled
// ruby_api files at engine init time. Engine api bytecode failing is fatal
// (it's our own code, not user code) so we panic with a clear message instead
// of returning to the caller. Generated bin/build code calls this for each
// `ruby_api/*__generated.bin`.
load_engine_bytecode :: proc(name: string, bytecode: []u8) {
	mrb.load_bytecode(g.mrb_state, bytecode)
	if mrb.has_exception(g.mrb_state) {
		log.errorf("Failed to instantiate engine component: %s", name)
		panic("EXITING")
	}
}

// load and execute main.rb. when the target directory has no main.rb, fall
// back to the embedded welcome screen (assets/welcome.rb baked into the
// binary via #load — never written to the user's filesystem).
load_main_rb :: proc() {
	contents: []byte
	filename: cstring = "main.rb"
	owns_contents := false

	if file_exists("main.rb") {
		ok: bool
		contents, ok = read_entire_file("main.rb")
		if !ok { return }
		owns_contents = true
	} else {
		contents = welcome_rb
		filename = "<welcome>"
	}
	defer if owns_contents { delete(contents) }

	// set filename in global context for proper stack traces
	mrb.ccontext_filename(g.mrb_state, g.mrb_ctx, filename)

	// set target class to Object class for top-level constant assignment
	mrb.ccontext_set_target_class(g.mrb_ctx, mrb.class_get(g.mrb_state, "Object"))
	mrb.ccontext_set_keep_lv(g.mrb_ctx, true)

	// check if this is precompiled bytecode or source code
	if mrb.is_bytecode(contents) {
		// load_bytecode wires up target_class = Object so top-level
		// constant assignment (e.g. `PLAYER = ...`) lands in the right
		// place. Bottom-of-function exception check handles failure.
		_ = mrb.load_bytecode(g.mrb_state, contents)
	} else {
		// load as source code
		code_cstr := strings.clone_to_cstring(string(contents))
		defer delete(code_cstr)
		mrb.load_string_cxt(g.mrb_state, code_cstr, g.mrb_ctx)
	}

	if mrb.has_exception(g.mrb_state) {
		handle_ruby_exception(g.mrb_state, mrb.current_exception(g.mrb_state), .INIT)
		panic("[ENGINE] main.rb execution failed with exception")
	}
}
