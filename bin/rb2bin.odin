package main

import "core:c"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import mrb "lib:mruby"

Args :: struct {
	input_file:  string `args:"pos=0" usage:"Input Ruby file"`,
	output_file: string `args:"pos=1" usage:"Output binary file"`,
	debug:       bool `flag:"debug" usage:"Include debug information in bytecode"`,
}

main :: proc() {
	args := Args{}

	err := flags.parse(&args, os.args[1:], .Unix)
	if err != nil {
		flags.print_errors(Args, err, os.args[0], .Unix)
		os.exit(1)
	}

	if !os.exists(args.input_file) {
		fmt.eprintfln("Error: Input file '%s' not found", args.input_file)
		os.exit(1)
	}

	mrb_state := mrb.open()
	mrb_ctx := mrb.ccontext_new(mrb_state)
	mrb_ctx.bitfields |= mrb.CCONTEXT_NO_EXEC
	defer mrb.close(mrb_state)
	defer mrb.ccontext_free(mrb_state, mrb_ctx)

	source_bytes, _ := os.read_entire_file(args.input_file)
	defer delete(source_bytes)

	input_file_cstr := strings.clone_to_cstring(args.input_file)
	defer delete(input_file_cstr)
	mrb.ccontext_filename(mrb_state, mrb_ctx, input_file_cstr)

	source_cstr := strings.clone_to_cstring(string(source_bytes))
	defer delete(source_cstr)
	result := mrb.load_string_cxt(mrb_state, source_cstr, rawptr(mrb_ctx))
	rproc := cast(^mrb.RProc)(uintptr(result.w))

	bin: rawptr
	bin_size: c.size_t
	mrb.dump_irep(mrb_state, rproc.body_irep, 0, &bin, &bin_size)

	bytecode := ([^]u8)(bin)[:bin_size]
	os.write_entire_file(args.output_file, bytecode)

	fmt.printfln("✓ Compiled %s (%d bytes bytecode)", args.input_file, bin_size)
}
