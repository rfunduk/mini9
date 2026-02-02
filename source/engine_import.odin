package engine

import "core:log"
import "core:os"
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
		panic("[ENGINE] ERROR: import() requires at least one argument")
	}

	args := (cast([^]mrb.Value)argv)[:argc]
	path_parts: [dynamic]string
	defer {
		for part in path_parts { delete(part) }
		delete(path_parts)
	}

	if argc == 1 {
		// single argument - convert to string and check if it contains '/'
		arg := args[0]
		str_obj := mrb.obj_as_string(state, arg)
		path_cstr := mrb.str_to_cstr(state, str_obj)
		full_path := strings.clone_from_cstring(path_cstr)
		defer delete(full_path)

		// if it contains '/', treat as path; otherwise treat as single module
		if strings.contains(full_path, "/") {
			// string path like "robot/states/idle"
			parts := strings.split(full_path, "/")
			defer delete(parts)
			for part in parts { append(&path_parts, strings.clone(part)) }
		} else {
			// single module like :robot or "robot"
			append(&path_parts, strings.clone(full_path))
		}
	} else {
		// multiple arguments like import(:robot, :states, :idle)
		for arg in args {
			str_obj := mrb.obj_as_string(state, arg)
			part_cstr := mrb.str_to_cstr(state, str_obj)
			part := strings.clone_from_cstring(part_cstr)
			append(&path_parts, part)
		}
	}

	// build file path
	module_path := strings.join(path_parts[:], "/")
	defer delete(module_path)

	filename, _ := strings.concatenate({module_path, ".rb"}, context.temp_allocator)

	contents, ok := read_entire_file(filename)
	if !ok {
		log.errorf("Could not load %s", filename)
		os.exit(1)
	}
	defer delete(contents)

	filename_cstr := strings.clone_to_cstring(filename)
	defer delete(filename_cstr)
	mrb.ccontext_filename(state, g.mrb_ctx, filename_cstr)

	// set target class to Object class for top-level constant assignment
	mrb.ccontext_set_target_class(g.mrb_ctx, mrb.class_get(state, "Object"))
	mrb.ccontext_set_keep_lv(g.mrb_ctx, true)

	// check if this is bytecode or source code
	result: mrb.Value
	if is_mruby_bytecode(contents) {
		// unfortunately this is just really hard to get working, mainly because
		// load_string_cxt and load_irep_cxt do fundamentally different things.
		// there is support here _in theory_ for doing this, but in practice it's
		// not ready yet
		panic("Not Implemented")

		// // use proper pattern: read_irep_buf -> proc_new -> proc_set_target_class -> exec_irep
		// irep := mrb.read_irep_buf(state, raw_data(contents), len(contents))
		// if irep == nil {
		// 	panic(fmt.tprintf("[ENGINE] ERROR: Could not read irep from %s", filename))
		// }

		// // create proc from irep
		// rproc := mrb.proc_new(state, irep)
		// if rproc == nil {
		// 	panic(fmt.tprintf("[ENGINE] ERROR: Could not create proc from %s", filename))
		// }

		// // set target class for constant resolution
		// target_class := mrb.class_get(state, "Object")
		// mrb.proc_set_target_class(rproc, target_class)

		// // execute with top_self context (same as source code loading)
		// result = mrb.exec_irep(state, mrb.top_self(state), rproc)
	} else {
		// load as source code
		code_cstr := strings.clone_to_cstring(string(contents))
		defer delete(code_cstr)
		result = mrb.load_string_cxt(state, code_cstr, g.mrb_ctx)
	}

	if has_ruby_exception(state) {
		log.errorf("Could not load %s", filename)
		os.exit(1)
	}

	return result
}
