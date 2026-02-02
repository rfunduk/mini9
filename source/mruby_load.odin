package engine

import "core:log"
import "core:os"
import "core:strings"
import mrb "lib:mruby"

// check if data is mruby bytecode (starts with "RITE" + version pattern)
is_mruby_bytecode :: proc(data: []u8) -> bool {
	if len(data) < 8 { return false }

	// check for "RITE" magic
	if !(data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x54 && data[3] == 0x45) {
		return false
	}

	// check that next 4 bytes look like version (digits/printable ASCII)
	// mruby versions are typically like "0300", "0301" etc.
	for i in 4 ..< 8 {
		if data[i] < 0x30 || data[i] > 0x39 { 	// not 0-9
			return false
		}
	}

	return true
}

load_bytecode :: proc(name: string, bytecode: []u8) {
	mrb.load_irep_cxt(g.mrb_state, raw_data(bytecode), g.mrb_ctx)
	if has_ruby_exception(g.mrb_state) {
		log.errorf("Failed to instantiate engine component: %s", name)
		os.exit(1)
	}
}

// load and execute main.rb
load_main_rb :: proc() {
	if !file_exists("main.rb") {
		// TODO: Create helpful hello world template
		return
	}

	contents, ok := read_entire_file("main.rb")
	if !ok { return }
	defer delete(contents)

	// set filename in global context for proper stack traces
	mrb.ccontext_filename(g.mrb_state, g.mrb_ctx, "main.rb")

	// set target class to Object class for top-level constant assignment
	mrb.ccontext_set_target_class(g.mrb_ctx, mrb.class_get(g.mrb_state, "Object"))
	mrb.ccontext_set_keep_lv(g.mrb_ctx, true)

	// check if this is bytecode or source code
	if is_mruby_bytecode(contents) {
		// unfortunately this is just really hard to get working, mainly because
		// load_string_cxt and load_irep_cxt do fundamentally different things.
		// there is support here _in theory_ for doing this, but in practice it's
		// not ready yet
		panic("Not Implemented")

		// // read_irep_buf -> proc_new -> proc_set_target_class -> exec_irep
		// irep := mrb.read_irep_buf(g.mrb_state, raw_data(contents), len(contents))
		// if irep == nil {
		// 	panic("[ENGINE] ERROR: Could not read irep from main.rb")
		// }

		// // create proc from irep
		// rproc := mrb.proc_new(g.mrb_state, irep)
		// if rproc == nil {
		// 	panic("[ENGINE] ERROR: Could not create proc from main.rb")
		// }

		// // set target class for constant resolution
		// target_class := mrb.class_get(g.mrb_state, "Object")
		// mrb.proc_set_target_class(rproc, target_class)

		// // use load_irep_cxt but ensure target class is properly set first
		// fmt.printfln("[DEBUG] Executing main.rb bytecode with context...")
		// // make sure context has the right target class set
		// g.mrb_ctx.target_class = target_class
		// result := mrb.load_irep_cxt(g.mrb_state, raw_data(contents), g.mrb_ctx)
		// fmt.printfln("[DEBUG] main.rb execution result: %v", result)
	} else {
		// load as source code
		code_cstr := strings.clone_to_cstring(string(contents))
		defer delete(code_cstr)
		mrb.load_string_cxt(g.mrb_state, code_cstr, g.mrb_ctx)
	}

	if has_ruby_exception(g.mrb_state) {
		// get the exception from mrb->exc directly
		offset: uintptr = 32 // mrb->exc offset on 64-bit
		when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 { offset = 16 }
		exc_ptr := cast(^rawptr)(uintptr(g.mrb_state) + offset)
		exc := mrb.Value {
			w = uintptr(exc_ptr^),
		}

		handle_ruby_exception(exc, .INIT)
		panic("[ENGINE] main.rb execution failed with exception")
	}
}
