package engine

import "core:strings"
import mrb "lib:mruby"

Data_File :: struct {
	path:    string,
	content: string,
}

ruby_datafile_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		file_ptr := cast(^Data_File)ptr
		delete(file_ptr.content)
		mrb.free(state, ptr)
	}
}

create_file :: proc(path: string) -> mrb.Value {
	path_str := string(path)
	file_data, ok := read_entire_file(path_str)
	if !ok {
		return mrb.raise_error(g.mrb_state, "RuntimeError", "Could not load file: %s", path_str)
	}
	defer delete(file_data)

	return file_from_data(path, file_data)
}

file_from_data :: proc(path: string, data: []u8) -> mrb.Value {
	file_class := mrb.class_get(g.mrb_state, "DataFile")
	ruby_obj := mrb.obj_new(g.mrb_state, file_class, 0, nil)

	str := strings.clone_from_bytes(data)
	file_ptr := mrb.alloc(g.mrb_state, Data_File{path = path, content = str})

	// set @path instance variable
	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	mrb.data_init(ruby_obj, file_ptr, NATIVE_TO_MRUBY_TYPE[Data_File])

	return ruby_obj
}

// RUBY FUNCTION: file(path=nil) -> returns FileData object
// @engine_method: name="file", aspec=ARGS_REQ(1)
ruby_file :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val: mrb.Value
	mrb.get_args(state, "o", &path_val)

	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := string(c_str)

	result := create_file(path)
	return result
}

ruby_file_get_lines :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	file := extract_native(Data_File, self)

	lines_array := mrb.ary_new(g.mrb_state)
	for line in strings.split_lines(file.content, context.temp_allocator) {
		cleaned := strings.trim_space(line)
		if len(cleaned) == 0 { continue }
		rstr := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(cleaned, context.temp_allocator))
		mrb.ary_push(g.mrb_state, lines_array, rstr)
	}

	return lines_array
}

setup_data_file :: proc() {
	c := mrb.get_data_class(g.mrb_state, "DataFile")
	mrb.define_method(g.mrb_state, c, "lines", cast(rawptr)ruby_file_get_lines, mrb.ARGS_NONE)
}
