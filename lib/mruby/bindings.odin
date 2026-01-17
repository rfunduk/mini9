package mruby

import "core:c"

MRUBY_LIB :: #config(MRUBY_LIB, "libmruby.a")
MRUBY_WASM_LIB :: #config(MRUBY_WASM_LIB, "libmruby_wasm.a")

when ODIN_OS == .Linux || ODIN_OS == .Darwin {
	foreign import lib {MRUBY_LIB}
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	foreign import lib {MRUBY_WASM_LIB}
} else when ODIN_OS == .Windows {
	foreign import lib {MRUBY_LIB}
}

Value :: struct {
	w: uintptr,
}

FALSE :: Value{4}
TRUE :: Value{12}
NIL :: Value{0}

// mrb_state structure - partial definition for GC access
State :: struct {
	jmp:           rawptr,
	c:             rawptr,
	root_c:        rawptr,
	globals:       rawptr,
	exc:           rawptr,
	top_self:      rawptr,
	object_class:  rawptr,
	class_class:   rawptr,
	module_class:  rawptr,
	proc_class:    rawptr,
	string_class:  rawptr,
	array_class:   rawptr,
	hash_class:    rawptr,
	range_class:   rawptr,
	float_class:   rawptr,
	integer_class: rawptr,
	true_class:    rawptr,
	false_class:   rawptr,
	nil_class:     rawptr,
	symbol_class:  rawptr,
	kernel_module: rawptr,
	gc:            GC,
}

Sym :: u32  // mrb_sym is uint32_t

// mrb_int definition - matches mruby's typedef
when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	Int :: i32 // WASM uses 32-bit
} else {
	Int :: i64 // Native builds use 64-bit
}

// mrb_kwargs structure for keyword argument handling
Kwargs :: struct {
	num:      Int, // number of keyword arguments
	required: Int, // number of required keyword arguments
	table:    ^Sym, // C array of symbols for keyword names
	values:   ^Value, // keyword argument values
	rest:     ^Value, // keyword rest (dict)
}

// mruby type constants (from mruby/value.h)
TT_FALSE :: 0
TT_TRUE :: 1
TT_SYMBOL :: 2
TT_UNDEF :: 3
TT_FREE :: 4
TT_FLOAT :: 5
TT_INTEGER :: 6
TT_PROC :: 16

// mruby data types for DATA objects
Data_Type :: struct {
	struct_name: cstring,
	dfree:       proc "c" (mrb: ^State, ptr: rawptr),
}

// basic mruby object header (MRB_OBJECT_HEADER)
// C bitfields: tt:8, gc_color:3, frozen:1, flags:20 packed into single 32-bit word
RBasic :: struct {
	class_ptr:   rawptr, // struct RClass *c
	gcnext:      rawptr, // struct RBasic *gcnext
	packed_bits: u32, // tt:8, gc_color:3, frozen:1, flags:20 (32 bits total)
}

// float object structure (for 32-bit WASM when MRB_WORDBOX_NO_FLOAT_TRUNCATE)
RFloat :: struct {
	using _: RBasic, // inherits basic header
	f:       f64, // the actual float value - mrb_float is double unless MRB_USE_FLOAT32 is defined
}

// RClass structure (matching mruby/class.h and object.h)
RClass :: struct {
	// MRB_OBJECT_HEADER fields (from mruby/object.h)
	class_ptr:   rawptr, // struct RClass *c
	gcnext:      rawptr, // struct RBasic *gcnext
	packed_bits: u32, // tt:8, gc_color:3, frozen:1, flags:20 (32 bits total)

	// RClass-specific fields (from mruby/class.h)
	iv:          rawptr, // struct iv_tbl *iv
	mt:          rawptr, // struct mt_tbl *mt
	super:       ^RClass, // struct RClass *super
}

// GC structure (matching mruby/gc.h)
GC :: struct {
	heaps:              rawptr, // struct mrb_heap_page *heaps
	free_heaps:         rawptr, // struct mrb_heap_page *free_heaps
	sweeps:             rawptr, // struct mrb_heap_page *sweeps
	gray_list:          rawptr, // struct RBasic *gray_list
	atomic_gray_list:   rawptr, // struct RBasic *atomic_gray_list
	live:               uint, // size_t live
	live_after_mark:    uint, // size_t live_after_mark
	threshold:          uint, // size_t threshold
	oldgen_threshold:   uint, // size_t oldgen_threshold
	state:              u32, // mrb_gc_state state
	interval_ratio:     i32, // int interval_ratio
	step_ratio:         i32, // int step_ratio
	current_white_part: u8, // unsigned int current_white_part:2
	iterating:          bool, // mrb_bool iterating:1
	disabled:           bool, // mrb_bool disabled:1
	generational:       bool, // mrb_bool generational:1
	full:               bool, // mrb_bool full:1
	out_of_memory:      bool, // mrb_bool out_of_memory:1
	// arena fields - positioned exactly as in mruby/gc.h
	arena:              rawptr, // struct RBasic **arena (or fixed array)
	arena_capa:         i32, // int arena_capa (only if !MRB_GC_FIXED_ARENA)
	arena_idx:          i32, // int arena_idx
}

// RData structure (matching mruby/data.h and object.h)
RData :: struct {
	// MRB_OBJECT_HEADER fields (from mruby/object.h)
	class_ptr:   rawptr, // struct RClass *c
	gcnext:      rawptr, // struct RBasic *gcnext
	packed_bits: u32, // tt:8, gc_color:3, frozen:1, flags:20 (32 bits total)

	// RData-specific fields (from mruby/data.h)
	iv:          rawptr, // instance variables table
	type:        ^Data_Type, // pointer to data type
	data:        rawptr, // pointer to actual data
}

RHash :: map[string]Value

TT_DATA :: 0x0D // from mruby source: enum mrb_vtype
TT_ARRAY :: 17 // from mruby source: enum mrb_vtype
INSTANCE_TT_MASK :: 0x1F // bits 0-5 for instance type

// compiler context (mrb_ccontext)
CContext :: struct {
	syms:         ^Sym, // mrb_sym *syms
	slen:         c.int, // int slen
	filename:     cstring, // char *filename
	lineno:       u16, // uint16_t lineno
	partial_hook: rawptr, // int (*partial_hook)(struct mrb_parser_state*)
	partial_data: rawptr, // void *partial_data
	target_class: rawptr, // struct RClass *target_class
	// the bitfields are packed into a single byte or word
	bitfields:    u8, // capture_errors:1, dump_result:1, no_exec:1, keep_lv:1, no_optimize:1, no_ext_ops:1
	upper:        rawptr, // const struct RProc *upper
	parser_nerr:  c.size_t, // size_t parser_nerr
}

// bit positions for the bitfields
CCONTEXT_CAPTURE_ERRORS :: 0x01
CCONTEXT_DUMP_RESULT :: 0x02
CCONTEXT_NO_EXEC :: 0x04
CCONTEXT_KEEP_LV :: 0x08
CCONTEXT_NO_OPTIMIZE :: 0x10
CCONTEXT_NO_EXT_OPS :: 0x20

// RProc structure based on actual mruby source
RProc :: struct {
	using _:        RBasic, // MRB_OBJECT_HEADER
	body_irep:      rawptr, // union { const mrb_irep *irep; mrb_func_t func; mrb_sym mid; }
	upper:          rawptr, // const struct RProc *upper
	e_target_class: rawptr,
}

RArray :: struct {
	using _: RBasic, // MRB_OBJECT_HEADER
	as:      struct #raw_union {
		heap: struct {
			len: Int, // mrb_ssize
			aux: struct #raw_union {
				capa:   Int, // mrb_ssize
				shared: rawptr, // mrb_shared_array*
			},
			ptr: ^Value, // mrb_value*
		},
		ary:  [3]Value, // MRB_ARY_EMBED_LEN_MAX
	},
}

@(link_prefix = "mrb_")
@(default_calling_convention = "c")
foreign lib {
	// core mruby functions
	open :: proc() -> ^State ---
	close :: proc(state: ^State) ---

	// code execution
	load_string :: proc(state: ^State, code: cstring) -> Value ---
	load_string_cxt :: proc(state: ^State, code: cstring, cxt: rawptr) -> Value ---

	// context management
	ccontext_new :: proc(state: ^State) -> ^CContext ---
	ccontext_free :: proc(state: ^State, cxt: ^CContext) ---
	ccontext_cleanup_local_variables :: proc(cxt: ^CContext) ---
	ccontext_filename :: proc(state: ^State, cxt: ^CContext, filename: cstring) -> cstring ---
	load_irep_cxt :: proc(state: ^State, irep: rawptr, cxt: ^CContext) -> Value ---
	load_irep :: proc(state: ^State, irep: rawptr) -> Value ---

	// method definition
	define_method :: proc(state: ^State, class: rawptr, name: cstring, func: rawptr, args: c.int) ---
	alias_method :: proc(state: ^State, class: rawptr, new_name: Sym, old_name: Sym) ---
	define_const :: proc(state: ^State, cla: rawptr, name: cstring, val: Value) ---

	// argument parsing
	get_args :: proc(state: ^State, format: cstring, #c_vararg args: ..any) -> c.int ---

	// block/Proc operations
	yield :: proc(state: ^State, b: Value, arg: Value) -> Value ---

	// exception-safe function execution
	protect :: proc(state: ^State, body: proc "c" (state: ^State, data: Value) -> Value, data: Value, exception_state: ^c.bool) -> Value ---

	// exception/backtrace printing
	print_backtrace :: proc(state: ^State) ---

	// value creation
	boxing_int_value :: proc(state: ^State, v: c.int) -> Value ---
	word_boxing_float_value :: proc(state: ^State, v: f64) -> Value ---

	// class operations
	class_get :: proc(state: ^State, name: cstring) -> rawptr ---
	obj_new :: proc(state: ^State, cls: rawptr, argc: c.int, argv: rawptr) -> Value ---

	// instance variable operations
	iv_set :: proc(state: ^State, obj: Value, sym: Sym, val: Value) ---
	iv_get :: proc(state: ^State, obj: Value, sym: Sym) -> Value ---

	// global variable operations
	gv_get :: proc(state: ^State, sym: Sym) -> Value ---
	gv_set :: proc(state: ^State, sym: Sym, val: Value) ---

	// symbol operations
	intern_cstr :: proc(state: ^State, str: cstring) -> Sym ---

	// string operations
	obj_as_string :: proc(state: ^State, obj: Value) -> Value ---
	string_value_cstr :: proc(state: ^State, str_obj: Value) -> cstring ---
	str_to_cstr :: proc(state: ^State, str: Value) -> cstring ---
	str_new_cstr :: proc(state: ^State, str: cstring) -> Value ---

	// hash operations
	hash_get :: proc(state: ^State, hash: Value, key: Value) -> Value ---
	hash_delete_key :: proc(state: ^State, hash: Value, key: Value) -> Value ---
	hash_keys :: proc(state: ^State, hash: Value) -> Value ---
	hash_size :: proc(state: ^State, hash: Value) -> c.int ---

	// array operations
	ary_new :: proc(state: ^State) -> Value ---
	ary_push :: proc(state: ^State, ary: Value, elem: Value) ---
	ary_entry :: proc(ary: Value, idx: c.int) -> Value ---

	// value inspection and conversion
	obj_classname :: proc(state: ^State, obj: Value) -> cstring ---

	// exception handling
	exc_backtrace :: proc(state: ^State, exc: Value) -> Value ---

	// module/kernel operations
	module_get :: proc(state: ^State, name: cstring) -> rawptr ---

	// function calling
	funcall :: proc(state: ^State, obj: Value, name: cstring, argc: c.int, #c_vararg argv: ..any) -> Value ---
	funcall_argv :: proc(state: ^State, obj: Value, name: Sym, argc: c.int, argv: rawptr) -> Value ---
	top_self :: proc(state: ^State) -> Value ---

	// bytecode execution
	exec_irep :: proc(state: ^State, self: Value, rproc: ^RProc) -> Value ---
	read_irep_buf :: proc(state: ^State, buf: rawptr, bufsize: c.size_t) -> rawptr ---
	proc_new :: proc(state: ^State, irep: rawptr) -> ^RProc ---
	vm_ci_target_class_set :: proc(ci: rawptr, target_class: rawptr) ---

	// method introspection
	respond_to :: proc(state: ^State, obj: Value, mid: Sym) -> bool ---

	// data object operations
	data_get_ptr :: proc(state: ^State, val: Value, type: ^Data_Type) -> rawptr ---
	data_check_get_ptr :: proc(state: ^State, val: Value, type: ^Data_Type) -> rawptr ---
	data_check_type :: proc(state: ^State, obj: Value, type: ^Data_Type) ---

	// memory management
	malloc :: proc(state: ^State, size: uintptr) -> rawptr ---
	free :: proc(state: ^State, ptr: rawptr) ---

	// GC protection
	gc_protect :: proc(state: ^State, obj: Value) ---
	gc_register :: proc(state: ^State, obj: Value) ---
	gc_unregister :: proc(state: ^State, obj: Value) ---

	// bytecode dumping
	dump_irep :: proc(state: ^State, irep: rawptr, flags: u8, bin: ^rawptr, bin_size: ^c.size_t) -> c.int ---
}
