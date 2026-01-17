package engine

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

ruby_allocate :: proc($T: typeid, val: T) -> ^T {
	ptr := cast(^T)mrb.malloc(g.mrb_state, size_of(T))
	ptr^ = val

	// here we give mruby a little slap to let it know that
	// the memory of this new object is bigger than it thought
	// this avoids extra memory pressure due to mruby not knowing
	// about how big these Rect objects are
	g.mrb_state.gc.threshold -= size_of(T)

	return ptr
}

// format mruby value as string, using simple format for basic types
ruby_format_value :: proc(state: ^mrb.State, val: mrb.Value) -> string {
	context = global_context

	if val == mrb.NIL { return "nil" }

	str_obj := mrb.obj_as_string(state, val)
	c_str := mrb.str_to_cstr(state, str_obj)
	result := string(c_str)

	return result
}

// parse kwargs hash into Odin map using temp allocator
parse_kwargs :: proc(state: ^mrb.State, kwargs: mrb.Value) -> mrb.RHash {
	context = global_context
	if kwargs == mrb.NIL { return {} }

	hash_size := mrb.hash_size(state, kwargs)
	if hash_size == 0 { return {} }

	hash := make(mrb.RHash, hash_size, context.temp_allocator)

	keys := mrb.hash_keys(state, kwargs)
	for i in 0 ..< hash_size {
		key := mrb.ary_entry(keys, i32(i))
		val := mrb.hash_get(state, kwargs, key)
		if val == mrb.NIL { continue }

		key_val := mrb.obj_as_string(state, key)
		key_name := string(mrb.str_to_cstr(state, key_val))

		hash[key_name] = val
	}

	return hash
}

ruby_hash_delete :: proc(state: ^mrb.State, hash: mrb.Value, key: string) {
	keys_array := mrb.hash_keys(state, hash)
	hash_size := mrb.hash_size(state, hash)

	for i in 0 ..< hash_size {
		actual_key := mrb.ary_entry(keys_array, i32(i))
		key_str := ruby_format_value(state, actual_key)

		// check if this matches what we're looking for
		if key_str == key {
			mrb.hash_delete_key(state, hash, actual_key)
			return
		}
	}
}

extract_native :: #force_inline proc($T: typeid, val: mrb.Value) -> ^T {
	when #config(CHECK_MRUBY_DATA_TYPES, false) {
		return cast(^T)mrb.data_check_get_ptr(g.mrb_state, val, NATIVE_TO_MRUBY_TYPE[T])
	} else {
		return cast(^T)mrb.data_get_ptr(g.mrb_state, val, NATIVE_TO_MRUBY_TYPE[T])
	}
}

create_data_class :: proc(name: string) -> rawptr {
	class := mrb.class_get(g.mrb_state, strings.clone_to_cstring(name))

	// set class to use DATA type
	mrb.set_instance_tt(class, mrb.TT_DATA)

	return class
}
