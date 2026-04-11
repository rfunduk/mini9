package engine

import "core:log"
import "core:strings"
import mrb "lib:mruby"

// RUBY FUNCTION: import(symbol) -> requires a module
// supports: import(:module), import("path/to/module"), import(:path, :to, :module)
// @engine_method: name="import", arity=-1
ruby_import :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	// get variadic arguments
	argv: ^mrb.Value
	argc: i32
	mrb.get_args(state, "*", &argv, &argc)

	if argc == 0 {
		return mrb.raise_error(state, "ArgumentError", "import() requires at least one argument")
	}

	args := (cast([^]mrb.Value)argv)[:argc]

	// path_parts and everything derived from it is purely intermediate state
	// used to build `filename`. nothing here outlives the function call, so we
	// use the temp allocator: no defers needed, and if we longjmp out via
	// ruby_raise the temp allocator handles cleanup at end-of-frame anyway.
	path_parts := make([dynamic]string, context.temp_allocator)

	if argc == 1 {
		// single argument - convert to string and check if it contains '/'
		arg := args[0]
		str_obj := mrb.obj_as_string(state, arg)
		path_cstr := mrb.str_to_cstr(state, str_obj)
		full_path := strings.clone_from_cstring(path_cstr, context.temp_allocator)

		// if it contains '/', treat as path; otherwise treat as single module
		if strings.contains(full_path, "/") {
			// string path like "robot/states/idle"
			for part in strings.split_iterator(&full_path, "/") {
				append(&path_parts, part)
			}
		} else {
			// single module like :robot or "robot"
			append(&path_parts, full_path)
		}
	} else {
		// multiple arguments like import(:robot, :states, :idle)
		for arg in args {
			str_obj := mrb.obj_as_string(state, arg)
			part_cstr := mrb.str_to_cstr(state, str_obj)
			part := strings.clone_from_cstring(part_cstr, context.temp_allocator)
			append(&path_parts, part)
		}
	}

	module_path := strings.join(path_parts[:], "/", context.temp_allocator)
	filename, _ := strings.concatenate({module_path, ".rb"}, context.temp_allocator)

	contents, ok := read_entire_file(filename)
	if !ok {
		return mrb.raise_error(state, "RuntimeError", "Could not load module: %s", filename)
	}
	defer delete(contents)

	// these only need to live across one synchronous mruby call each, so
	// temp_allocator is fine - mruby copies the strings internally.
	filename_cstr := strings.clone_to_cstring(filename, context.temp_allocator)
	mrb.ccontext_filename(state, g.mrb_ctx, filename_cstr)

	// set target class to Object class for top-level constant assignment
	mrb.ccontext_set_target_class(g.mrb_ctx, mrb.class_get(state, "Object"))
	mrb.ccontext_set_keep_lv(g.mrb_ctx, true)

	// check if this is precompiled bytecode or source code
	result: mrb.Value
	if mrb.is_bytecode(contents) {
		// load_bytecode wires up target_class = Object so top-level constant
		// assignment in imported user files lands in the right place.
		result = mrb.load_bytecode(state, contents)
	} else {
		// load as source code
		code_cstr := strings.clone_to_cstring(string(contents), context.temp_allocator)
		result = mrb.load_string_cxt(state, code_cstr, g.mrb_ctx)
	}

	if mrb.has_exception(state) {
		log.errorf("Could not load %s", filename)
		return mrb.NIL
	}

	return result
}
