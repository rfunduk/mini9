package mruby

import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"

// Engine-agnostic helpers built on top of the raw FFI bindings.
// Every proc here takes `State` explicitly so this file has no dependency
// on engine globals or other packages.

// mruby keeps the pending exception in `mrb_state->exc`. Since we treat
// `mrb_state` as opaque, we read/write that field via a fixed offset.
@(private)
exc_field :: #force_inline proc(state: State) -> ^rawptr {
	offset: uintptr = 32 // 64-bit native
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 { offset = 16 }
	return cast(^rawptr)(uintptr(state) + offset)
}

// True if `data` looks like compiled mruby bytecode (RITE magic + ASCII version).
is_bytecode :: proc(data: []u8) -> bool {
	if len(data) < 8 { return false }

	// RITE magic
	if !(data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x54 && data[3] == 0x45) {
		return false
	}

	// Next 4 bytes should be ASCII digits (e.g. "0300", "0301").
	for i in 4 ..< 8 {
		if data[i] < 0x30 || data[i] > 0x39 { return false }
	}

	return true
}

// Extract a numeric value as f64, accepting both fixnums and floats.
// Returns 0 for any other type.
to_f64 :: #force_inline proc(val: Value) -> f64 {
	if integer_p(val) { return f64(integer(val)) }
	if float_p(val) { return float(val) }
	return 0
}

// Extract a numeric value as an Odin int, accepting both integers and floats
// (float is truncated). Returns 0 for any other type.
to_int :: #force_inline proc(val: Value) -> int {
	if integer_p(val) { return int(integer(val)) }
	if float_p(val) { return int(float(val)) }
	return 0
}

// True iff `val` is an Integer or Float. The "is this a number at all" check,
// decoupled from extraction: pair with to_f64/to_int at a call site that wants
// to reject non-numerics instead of coercing them to 0.
numeric_p :: #force_inline proc(val: Value) -> bool {
	return integer_p(val) || float_p(val)
}

// True if `top_self` responds to a method named `name`.
function_exists :: proc(state: State, name: cstring) -> bool {
	if state == nil { return false }
	return respond_to(state, top_self(state), intern_cstr(state, name))
}

// True if the VM has a pending exception.
has_exception :: proc(state: State) -> bool {
	return exc_field(state)^ != nil
}

// The pending exception, or NIL if none.
current_exception :: proc(state: State) -> Value {
	return Value{w = uintptr(exc_field(state)^)}
}

// Install `exc` as the pending exception, returning whatever was there before.
// Useful for pairing exception extraction with `print_backtrace`, which reads
// from the live `mrb_state`.
swap_exception :: proc(state: State, exc: Value) -> Value {
	field := exc_field(state)
	old := Value {
		w = uintptr(field^),
	}
	field^ = cast(rawptr)exc.w
	return old
}

// Run a funcall, saving and restoring the GC arena around the call so the
// transient values it produces don't accumulate in the arena. Use this for
// the unprotected fast path; for callbacks where you need to catch exceptions
// in Odin land, use `protected_funcall` instead.
funcall_safe :: proc(state: State, obj: Value, method: cstring, argc: c.int = 0, argv: [^]Value = nil) {
	arena_idx := gc_arena_save(state)
	defer gc_arena_restore(state, arena_idx)
	_ = funcall_argv(state, obj, intern_cstr(state, method), argc, argv)
}

// Load and execute precompiled mruby bytecode at the top level. Wires up
// target_class = Object so top-level constants and method definitions land
// in the right place — see `load_irep_top` for the full story.
//
// Returns the value the proc evaluated to, mirroring the shape of
// `load_string_cxt` so the two are interchangeable. On exception the return
// value is undef/nil and `has_exception(state)` will be true — the caller
// is responsible for checking and routing the error.
load_bytecode :: proc(state: State, bytecode: []u8) -> Value {
	return load_irep_top(state, raw_data(bytecode), c.size_t(len(bytecode)))
}

// Allocate a native struct using mruby's allocator and nudge the GC
// threshold by the struct's size. mruby's GC normally only knows about
// the small Ruby data wrapper object, so larger native structs put unfair
// pressure on the GC budget — the threshold decrement compensates by
// making the next collection happen sooner. Use this whenever you're
// about to attach the result to a Ruby data object via `data_init`.
alloc :: proc(state: State, val: $T) -> ^T {
	ptr := cast(^T)malloc(state, size_of(T))
	ptr^ = val
	gc_threshold_decrement(state, size_of(T))
	return ptr
}

// Format a Ruby value as a string by calling its `to_s`. The returned
// string is BORROWED from mruby's internal cstring buffer — it's only
// valid until the next mruby allocation. Clone it if you need to keep it
// across mruby calls.
to_string :: proc(state: State, val: Value) -> string {
	if val == NIL { return "nil" }
	str := obj_as_string(state, val)
	return string(str_to_cstr(state, str))
}

// Look up a pre-interned symbol key in a kwargs hash. Returns NIL if the
// hash is NIL or the key is absent. Use with symbol values created via
// `symbol_value(intern_cstr(state, "key"))` at setup time.
kwarg :: #force_inline proc(state: State, hash: Value, key: Value) -> Value {
	if hash == NIL { return NIL }
	return hash_get(state, hash, key)
}

// Look up an existing Ruby class by name and tag it with the DATA
// instance type, so instances can carry a native pointer via `data_init`.
// Pairs with the `MRB_DEFINE_DATA_CLASS` pattern from mruby C examples.
get_data_class :: proc(state: State, name: string) -> rawptr {
	class := class_get(state, strings.clone_to_cstring(name, context.temp_allocator))
	set_instance_tt(class, TT_DATA)
	return class
}

// Define a Ruby class (subclass of Object) and tag it with DATA instance
// type. Must run BEFORE any bytecode creates instances of the class —
// otherwise those instances get TT_OBJECT storage and any subsequent
// `data_init` writes into the wrong offset.
define_data_class :: proc(state: State, name: string) -> rawptr {
	cname := strings.clone_to_cstring(name, context.temp_allocator)
	object_class := class_get(state, "Object")
	class := define_class(state, cname, object_class)
	set_instance_tt(class, TT_DATA)
	return class
}

// return arity of a proc, or 0 if nil passed
safe_proc_arity :: #force_inline proc(proc_val: Value) -> i32 {
	if proc_val == NIL { return 0 }
	return i32(proc_arity(proc_val))
}

// Inspect a value (calls `inspect`). Cloned into `allocator` because the
// underlying mruby cstring is invalidated by the next mruby allocation.
inspect :: proc(state: State, val: Value, allocator := context.allocator) -> string {
	if val == NIL { return strings.clone("nil", allocator) }
	s := funcall(state, val, "inspect", 0)
	return strings.clone(string(string_cstr(state, s)), allocator)
}

// Format a message and raise a Ruby exception of the named class. The
// message is logged via `core:log` for visibility (since the longjmp from
// `raise` skips any defers in the caller and won't otherwise leave a
// trace). Returns NIL so callers can write `return raise_error(...)` —
// the value is unreachable because `mrb_raise` never returns.
//
// Caller WARNING: must not be called from a scope with active defers,
// since the longjmp will skip them.
raise_error :: proc(state: State, exception_class: cstring, format: string, args: ..any) -> Value {
	msg := fmt.ctprintf(format, ..args)
	log.error(string(msg))
	exc := exc_get_id(state, intern_cstr(state, exception_class))
	raise(state, exc, msg)
	return NIL
}

// Run a funcall inside `mrb_protect`. On exception returns `(false, exc)`
// where `exc` is the raised value; on success returns `(true, NIL)`.
protected_funcall :: proc(
	state: State,
	obj: Value,
	method: cstring,
	argc: c.int = 0,
	argv: [^]Value = nil,
) -> (
	ok: bool,
	exc: Value,
) {
	args := Funcall_Args {
		obj    = obj,
		method = method,
		argc   = argc,
		argv   = argv,
	}
	data := Value {
		w = uintptr(&args),
	}
	exception_occurred: c.bool = false
	result := protect(state, funcall_dispatch, data, &exception_occurred)
	return !exception_occurred, result
}

// Yield to a block via `mrb_yield` inside `mrb_protect`. Same return shape
// as `protected_funcall`.
protected_yield :: proc(state: State, block: Value, arg: Value) -> (ok: bool, exc: Value) {
	args := Yield_Args {
		block = block,
		arg   = arg,
	}
	data := Value {
		w = uintptr(&args),
	}
	exception_occurred: c.bool = false
	result := protect(state, yield_dispatch, data, &exception_occurred)
	return !exception_occurred, result
}

// --- protect dispatcher internals ---
//
// `mrb_protect`'s callback signature is `proc "c" (state, data) -> Value`,
// so we have to pack arguments into the single `data` value. Each variant
// gets its own arg struct + dispatcher proc; no shared union, no context
// line in the dispatcher body (every call inside is foreign C — nothing
// touches Odin runtime).

@(private)
Funcall_Args :: struct {
	obj:    Value,
	method: cstring,
	argc:   c.int,
	argv:   [^]Value,
}

@(private)
Yield_Args :: struct {
	block: Value,
	arg:   Value,
}

@(private)
funcall_dispatch :: proc "c" (state: State, data: Value) -> Value {
	args := cast(^Funcall_Args)ptr(data)
	_ = funcall_argv(state, args.obj, intern_cstr(state, args.method), args.argc, args.argv)
	return NIL
}

@(private)
yield_dispatch :: proc "c" (state: State, data: Value) -> Value {
	args := cast(^Yield_Args)ptr(data)
	_ = yield(state, args.block, args.arg)
	return NIL
}
