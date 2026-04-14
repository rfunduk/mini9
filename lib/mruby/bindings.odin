package mruby

import "core:c"

foreign import lib {#config(MRUBY_LIB, "libmruby.a")}
foreign import macros {#config(MRUBY_MACROS_LIB, "macros.a")}

Value :: struct {
	w: uintptr,
}

FALSE :: Value{4}
TRUE :: Value{12}
NIL :: Value{0}

State :: distinct rawptr
Sym :: u32

when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	Int :: i32 // WASM uses 32-bit
} else {
	Int :: i64 // Native builds use 64-bit
}

TT_DATA :: 13
Data_Type :: struct {
	struct_name: cstring,
	dfree:       proc "c" (mrb: State, ptr: rawptr),
}

RData :: distinct rawptr
CContext :: distinct rawptr
RProc :: distinct rawptr

@(link_prefix = "mrb_")
@(default_calling_convention = "c")
foreign lib {
	// core mruby functions
	open :: proc() -> State ---
	close :: proc(state: State) ---

	// code execution
	load_string_cxt :: proc(state: State, code: cstring, cxt: rawptr) -> Value ---

	// context management
	ccontext_new :: proc(state: State) -> CContext ---
	ccontext_free :: proc(state: State, cxt: CContext) ---
	ccontext_filename :: proc(state: State, cxt: CContext, filename: cstring) -> cstring ---
	load_irep_cxt :: proc(state: State, irep: rawptr, cxt: CContext) -> Value ---
	load_irep :: proc(state: State, irep: rawptr) -> Value ---

	// method definition
	define_method :: proc(state: State, class: rawptr, name: cstring, func: rawptr, args: c.int) ---
	define_module_function :: proc(state: State, mod: rawptr, name: cstring, func: rawptr, args: c.int) ---
	alias_method :: proc(state: State, class: rawptr, new_name: Sym, old_name: Sym) ---
	define_const :: proc(state: State, cla: rawptr, name: cstring, val: Value) ---

	// argument parsing
	get_args :: proc(state: State, format: cstring, #c_vararg args: ..any) -> c.int ---

	// block/Proc operations
	yield :: proc(state: State, b: Value, arg: Value) -> Value ---

	// exception-safe function execution
	protect :: proc(state: State, body: proc "c" (state: State, data: Value) -> Value, data: Value, exception_state: ^c.bool) -> Value ---

	// exception/backtrace printing
	print_backtrace :: proc(state: State) ---

	// value creation
	boxing_int_value :: proc(state: State, v: c.int) -> Value ---
	word_boxing_float_value :: proc(state: State, v: f64) -> Value ---

	// class operations
	class_get :: proc(state: State, name: cstring) -> rawptr ---
	obj_new :: proc(state: State, cls: rawptr, argc: c.int, argv: rawptr) -> Value ---

	// instance variable operations
	iv_set :: proc(state: State, obj: Value, sym: Sym, val: Value) ---
	iv_get :: proc(state: State, obj: Value, sym: Sym) -> Value ---

	// global variable operations
	gv_get :: proc(state: State, sym: Sym) -> Value ---
	gv_set :: proc(state: State, sym: Sym, val: Value) ---

	// symbol operations
	intern_cstr :: proc(state: State, str: cstring) -> Sym ---

	// string operations
	obj_as_string :: proc(state: State, obj: Value) -> Value ---
	// note: mrb_string_value_cstr takes mrb_value* (pointer), not by value —
	// mruby may modify str in place (e.g. to ensure NUL-termination)
	string_value_cstr :: proc(state: State, str: ^Value) -> cstring ---
	str_to_cstr :: proc(state: State, str: Value) -> cstring ---
	str_new_cstr :: proc(state: State, str: cstring) -> Value ---

	// hash operations
	hash_get :: proc(state: State, hash: Value, key: Value) -> Value ---
	hash_delete_key :: proc(state: State, hash: Value, key: Value) -> Value ---
	hash_keys :: proc(state: State, hash: Value) -> Value ---
	hash_size :: proc(state: State, hash: Value) -> c.int ---

	// array operations
	ary_new :: proc(state: State) -> Value ---
	ary_push :: proc(state: State, ary: Value, elem: Value) ---
	ary_entry :: proc(ary: Value, idx: c.int) -> Value ---

	// value inspection and conversion
	obj_classname :: proc(state: State, obj: Value) -> cstring ---

	// exception handling
	exc_backtrace :: proc(state: State, exc: Value) -> Value ---
	exc_get_id :: proc(state: State, name: Sym) -> rawptr ---
	raise :: proc(state: State, exc_class: rawptr, msg: cstring) ---
	raisef :: proc(state: State, exc_class: rawptr, fmt: cstring, #c_vararg args: ..any) ---

	// string operations
	string_cstr :: proc(state: State, str: Value) -> cstring ---

	// module/kernel operations
	module_get :: proc(state: State, name: cstring) -> rawptr ---

	// function calling
	funcall :: proc(state: State, obj: Value, name: cstring, argc: c.int, #c_vararg argv: ..any) -> Value ---
	funcall_argv :: proc(state: State, obj: Value, name: Sym, argc: c.int, argv: rawptr) -> Value ---
	top_self :: proc(state: State) -> Value ---

	// bytecode execution
	exec_irep :: proc(state: State, self: Value, rproc: RProc) -> Value ---
	read_irep_buf :: proc(state: State, buf: rawptr, bufsize: c.size_t) -> rawptr ---
	proc_new :: proc(state: State, irep: rawptr) -> RProc ---

	// method introspection
	respond_to :: proc(state: State, obj: Value, mid: Sym) -> bool ---

	// data object operations
	data_get_ptr :: proc(state: State, val: Value, type: ^Data_Type) -> rawptr ---
	data_check_get_ptr :: proc(state: State, val: Value, type: ^Data_Type) -> rawptr ---

	// memory management
	malloc :: proc(state: State, size: uintptr) -> rawptr ---
	free :: proc(state: State, ptr: rawptr) ---

	// GC protection
	gc_register :: proc(state: State, obj: Value) ---
	gc_unregister :: proc(state: State, obj: Value) ---

	// bytecode dumping
	dump_irep :: proc(state: State, irep: rawptr, flags: u8, bin: ^rawptr, bin_size: ^c.size_t) -> c.int ---
}

// mruby macro library - thin C wrappers for mruby macros
@(link_prefix = "mrbm_")
@(default_calling_convention = "c")
foreign macros {
	// Type checking
	integer_p :: proc(val: Value) -> bool ---
	float_p :: proc(val: Value) -> bool ---
	symbol_p :: proc(val: Value) -> bool ---
	array_p :: proc(val: Value) -> bool ---
	string_p :: proc(val: Value) -> bool ---
	hash_p :: proc(val: Value) -> bool ---
	proc_p :: proc(val: Value) -> bool ---
	data_p :: proc(val: Value) -> bool ---
	nil_p :: proc(val: Value) -> bool ---
	true_p :: proc(val: Value) -> bool ---
	false_p :: proc(val: Value) -> bool ---

	// Value extraction
	integer :: proc(val: Value) -> Int ---
	float :: proc(val: Value) -> f64 ---
	symbol :: proc(val: Value) -> Sym ---
	@(link_name = "mrbm_bool")
	boolean :: proc(val: Value) -> bool ---
	ptr :: proc(val: Value) -> rawptr ---

	// Value creation
	fixnum_value :: proc(i: Int) -> Value ---
	symbol_value :: proc(s: Sym) -> Value ---
	bool_value :: proc(b: bool) -> Value ---

	// Array operations
	ary_len :: proc(ary: Value) -> Int ---

	// Data object operations
	data_init :: proc(v: Value, ptr: rawptr, type: ^Data_Type) ---

	// Class operations
	set_instance_tt :: proc(class: rawptr, tt: c.int) ---

	// GC arena operations
	gc_arena_save :: proc(state: State) -> c.int ---
	gc_arena_restore :: proc(state: State, idx: c.int) ---

	// GC state access (allows making mrb_state opaque)
	gc_live :: proc(state: State) -> uint ---
	gc_threshold :: proc(state: State) -> uint ---
	gc_threshold_decrement :: proc(state: State, amount: uint) ---

	// CContext operations (allows making mrb_ccontext opaque)
	ccontext_set_target_class :: proc(cxt: rawptr, target_class: rawptr) ---
	ccontext_set_keep_lv :: proc(cxt: rawptr, val: bool) ---
	ccontext_set_no_exec :: proc(cxt: rawptr, val: bool) ---

	// RProc operations (allows making RProc opaque)
	proc_irep :: proc(rproc: rawptr) -> rawptr ---
	proc_set_target_class :: proc(state: State, rproc: rawptr, target_class: rawptr) ---
	proc_arity :: proc(val: Value) -> Int ---
	method_arity :: proc(state: State, obj: Value, mid: Sym) -> Int ---

	// Exception operations - reads RException->mesg directly (no funcall,
	// no interpreter state required - safe to call from inside error handling)
	exc_mesg :: proc(state: State, exc: Value) -> Value ---

	// Load precompiled irep at top level with target_class wired up to Object,
	// the way mrb_load_exec does for source-loaded files. The stock
	// mrb_load_irep_cxt skips the target_class setup, which makes top-level
	// constant assignment (e.g. `FOO = ...` in a user main.rb) silently break.
	// Use this instead of load_irep_cxt for any user-authored .rb file.
	load_irep_top :: proc(state: State, buf: rawptr, bufsize: c.size_t) -> Value ---
}
