package mruby

import "core:c"

// functions i've had to implement natively due to them being macros in mruby source

ptr :: #force_inline proc(val: Value) -> rawptr {
	return rawptr(uintptr(val.w))
}

// mrb_data_init inline function implementation
// sets the data pointer and type for a DATA object
data_init :: proc(v: Value, ptr: rawptr, type: ^Data_Type) {
	// v.w contains the pointer value as a uintptr
	// need to convert it to actual pointer type
	rdata := cast(^RData)uintptr(v.w)
	rdata.data = ptr
	rdata.type = type
	// set the tt field (lower 8 bits) to MRB_TT_DATA
	rdata.packed_bits = (rdata.packed_bits & 0xFFFFFF00) | u32(TT_DATA)
}

// mrb_set_instance_tt implementation
// sets the instance type for a class (equivalent to MRB_SET_INSTANCE_TT macro)
set_instance_tt :: proc(class: rawptr, type: c.int) {
	rclass := cast(^RClass)class
	// extract current flags (bits 12-31) which are the top 20 bits
	flags_portion := (rclass.packed_bits >> 12) & 0xFFFFF
	// apply the MRB_SET_INSTANCE_TT logic to the flags portion
	new_flags := (flags_portion & ~u32(INSTANCE_TT_MASK)) | u32(type)
	// reconstruct the packed_bits: keep tt (bits 0-7), gc_color (bits 8-10), frozen (bit 11)
	rclass.packed_bits = (rclass.packed_bits & 0xFFF) | (new_flags << 12)
}

arena_save :: proc(state: ^State) -> i32 {
	return state.gc.arena_idx
}

arena_restore :: proc(state: ^State, idx: i32) {
	state.gc.arena_idx = idx
}


// helper to extract type tag from RBasic packed_bits
basic_tt :: #force_inline proc(basic: ^RBasic) -> u8 {
	return u8(basic.packed_bits & 0xFF) // tt is in lower 8 bits
}

bool_p :: #force_inline proc(val: Value) -> bool {
	return val == TRUE || val == FALSE
}

sym_p :: #force_inline proc(val: Value) -> bool {
	when size_of(uintptr) == 8 {
		// 64-bit inline float: symbol flag is 0x1c, mask is 0x1f
		return (val.w & 0x1f) == 0x1c
	} else {
		// 32-bit NO_FLOAT_TRUNCATE: symbol flag is 0x2, mask is 0x3
		return (val.w & 3) == 2
	}
}

// mrb_symbol_value inline - creates a symbol value from a Sym
symbol_value :: #force_inline proc(sym: Sym) -> Value {
	when size_of(uintptr) == 8 {
		// 64-bit inline float: symbol in upper 32 bits, flag 0x1c
		return Value{w = (uintptr(sym) << 32) | 0x1c}
	} else {
		// 32-bit NO_FLOAT_TRUNCATE: shift by 2, flag 0x2
		return Value{w = (uintptr(sym) << 2) | 2}
	}
}

// implement mruby's type checking macros in Odin
integer_p :: #force_inline proc(val: Value) -> bool {
	// WORDBOX_SHIFT_VALUE_P(o, FIXNUM) || WORDBOX_OBJ_TYPE_P(o, INTEGER)
	// FIXNUM check: (val.w & WORDBOX_FIXNUM_MASK) == WORDBOX_FIXNUM_FLAG
	// WORDBOX_FIXNUM_FLAG = 1, WORDBOX_FIXNUM_MASK = 1
	return (val.w & 1) == 1 // FIXNUM (immediate integer)
	// note: We're not checking heap INTEGER objects for simplicity
}

float_p :: proc(val: Value) -> bool {
	when size_of(uintptr) == 4 {
		// 32-bit: MRB_WORDBOX_NO_FLOAT_TRUNCATE is set, so floats are heap objects
		// WORDBOX_OBJ_TYPE_P(o, FLOAT): (!mrb_immediate_p(o) && mrb_val_union(o).bp->tt == MRB_TT_FLOAT)

		// check if it's immediate
		if integer_p(val) { return false }
		if sym_p(val) { return false }
		if val == NIL || val == TRUE || val == FALSE { return false }

		basic_ptr := cast(^RBasic)uintptr(val.w)
		tt := basic_tt(basic_ptr)
		return tt == TT_FLOAT
	} else {
		// 64-bit: WORDBOX_SHIFT_VALUE_P(o, FLOAT)
		// WORDBOX_FLOAT_FLAG = 2, WORDBOX_FLOAT_MASK = 3
		// TODO what? why are wec hecking if it's a symbol here?
		return (val.w & 3) == 2
	}
}

number_p :: #force_inline proc(val: Value) -> bool {
	return integer_p(val) || float_p(val)
}

proc_p :: proc(val: Value) -> bool {
	// check if it's a proc/block (lambda, proc, or block passed to method)
	// in mruby: #define mrb_proc_p(o) (mrb_type(o) == MRB_TT_PROC)

	// check if it's immediate (procs are never immediate)
	if number_p(val) { return false }
	if sym_p(val) { return false }
	if val == NIL || val == TRUE || val == FALSE { return false }

	// it's a heap object - check the type tag
	basic_ptr := cast(^RBasic)uintptr(val.w)
	tt := basic_tt(basic_ptr)
	return tt == TT_PROC
}

immediate_p :: proc(val: Value) -> bool {
	// in mruby word boxing, immediate values have the w field set to special patterns
	// this is a simplified check - in full mruby it's more complex
	return val == NIL || (val.w & 0x1) != 0 || (val.w & 0x2) != 0
}

array_p :: proc(val: Value) -> bool {
	if immediate_p(val) { return false }
	// in mruby: #define mrb_array_p(o) (mrb_type(o) == MRB_TT_ARRAY)
	// MRB_TT_ARRAY = 8

	basic_ptr := cast(^RBasic)rawptr(uintptr(val.w))
	if basic_ptr == nil {
		return false
	}

	tt := basic_tt(basic_ptr)
	return tt == TT_ARRAY
}


integer :: proc(boxed_integer: Value) -> c.int {
	return c.int(boxed_integer.w >> 1)
}

float :: proc(val: Value, loc := #caller_location) -> f64 {
	// use proper type checking and handle both integers and floats
	if integer_p(val) {
		// it's an integer, convert to float
		return f64(integer(val))
	} else if float_p(val) {
		// it's a float, extract properly based on platform
		when size_of(uintptr) == 4 {
			// 32-bit: heap object, dereference the RFloat
			basic_ptr := cast(^RBasic)uintptr(val.w)
			float_ptr := cast(^RFloat)basic_ptr

			return float_ptr.f
		} else {
			// 64-bit: packed in word, transmute directly
			return transmute(f64)val.w
		}
	} else {
		return 0.0
	}
}

// boolean handling based on mruby's mrb_bool macro
// mrb_bool(o) returns true if the value is not false/nil
boolean :: proc(val: Value) -> bool {
	// in mruby, only false and nil are falsy
	return val != NIL && val != FALSE
}

// MRB_PROC_SET_TARGET_CLASS macro implementation
proc_set_target_class :: proc(rproc: ^RProc, target_class: rawptr) {
	// the macro sets rproc->e.target_class (simplified version)
	// full version would check MRB_PROC_ENV_P and handle env case
	if rproc != nil {
		rproc.e_target_class = target_class
	}
}
