#+build !wasm32
#+build !wasm64p32

package main_native

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "core:encoding/json"
import mrb "lib:mruby"

import engine ".."

@(private = "file")
mrb_state: mrb.State

@(private = "file")
mrb_ctx: mrb.CContext

@(private = "file")
rom_data: ^engine.Rom_Data

@(private = "file")
Package_Build :: struct {
	using metadata: engine.Rom_Metadata,

	// not user-authored — set to source dir basename at package time.
	// used as stable save-file identity (web localStorage key, etc)
	// so renaming the .m9 doesn't orphan saves.
	name:           string,

	// sizes used for loading progress on web
	rom_size:       i64,
	wasm_size:      i64,
	total_size:     i64,
}

packager :: proc(args: ^Args) {
	rom_data = new(engine.Rom_Data)

	// 1. handle args and set defaults
	args.source = args.source if len(args.source) > 0 else "."

	// make source path absolute for consistent relative path calculations
	abs_path, abs_err := filepath.abs(args.source, context.temp_allocator)
	if abs_err == nil { args.source = abs_path }

	if !os.is_dir(abs_path) {
		fmt.printfln("ERROR: Unable to package game at %s, source not found.", args.source)
	}

	metadata := load_package_metadata(args.source)
	metadata.name = filepath.base(args.source)
	args.output = prepare_output_path(args)

	fmt.printfln("Source: %s", args.source)
	fmt.printfln("Output: %s", args.output)

	files_to_include := find_files_to_include(args, metadata.exclude_patterns)

	fmt.printfln("\nPackaging %d files", len(files_to_include))

	// ensure main.rb exists
	main_rb_found := false
	for file_path in files_to_include {
		if strings.has_suffix(file_path, "main.rb") {
			main_rb_found = true
			break
		}
	}
	if !main_rb_found {
		fmt.eprintfln("ERROR: No main.rb found in source directory")
		os.exit(1)
	}

	// init mruby
	setup_mruby()

	// BYTECODE_PACKAGING (default true): when on, .rb files are precompiled
	// to mruby bytecode at package time. Catches syntax/codegen errors early
	// (at packaging instead of first run on a player's machine), shaves
	// startup parse cost, and obfuscates source. Disable with
	// -define:BYTECODE_PACKAGING=false to bundle raw source instead.
	for file_path in files_to_include {
		rel_path, _ := filepath.rel(args.source, file_path, context.temp_allocator)
		when #config(BYTECODE_PACKAGING, true) {
			if strings.has_suffix(file_path, ".rb") {
				rom_data[rel_path] = load_ruby_file(file_path, rel_path)
			} else {
				rom_data[rel_path] = load_asset_file(file_path, rel_path)
			}
		} else {
			rom_data[rel_path] = load_asset_file(file_path, rel_path)
		}
	}

	// dump cart data to binary format
	rom_binary := engine.rom_data_dump(rom_data, !args.web && !args.no_compress)
	if rom_binary == nil {
		fmt.eprintfln("ERROR: Failed to serialize cart data")
		os.exit(1)
	}

	// write cart file
	rom_output_file := args.output
	if args.web {
		// also write out web stuff
		rom_output_file, _ = filepath.join({rom_output_file, "cart.m9"}, context.temp_allocator)
		for web_asset in engine.web_assets {
			asset_path, _ := filepath.join({args.output, web_asset.name}, context.temp_allocator)
			write_err := os.write_entire_file(asset_path, web_asset.data)
			if write_err != nil {
				fmt.eprintfln("ERROR: Failed to write web asset: %s", web_asset.name)
				os.exit(1)
			}
		}
	}
	write_err := os.write_entire_file(rom_output_file, rom_binary)
	if write_err != nil {
		fmt.eprintfln("ERROR: Failed to write cart file: %s", args.output)
		os.exit(1)
	}

	if args.web {
		// for web we need to update the metadata in the html
		// and also calculate the size from ALL files not just the rom
		calculate_file_sizes(args.output, &metadata)
		update_html_metadata(args.output, metadata)
		fmt.printfln("\n⟶ Packaged for Web: %s (%d bytes)...", args.output, metadata.total_size)
	} else {
		fmt.printfln("\n⟶ Created cart: %s (%d bytes)", args.output, len(rom_binary))
	}

	// cleanup. each rom_data value is an owned slice from load_ruby_file
	// (bytecode) or load_asset_file (raw bytes). keys are temp_allocator
	// strings (rel_path) and don't need freeing. rom_binary is the
	// serialized buffer from rom_data_dump.
	for _, file_data in rom_data {
		delete(file_data)
	}
	delete(rom_data^)
	free(rom_data)
	delete(rom_binary)

	free_all(context.temp_allocator)
	mrb.ccontext_free(mrb_state, mrb_ctx)
	mrb.close(mrb_state)
}

setup_mruby :: proc() {
	mrb_state = mrb.open()
	if mrb_state == nil {
		fmt.eprintfln("Error: Failed to initialize mruby")
		os.exit(1)
	}

	mrb_ctx = mrb.ccontext_new(mrb_state)
	if mrb_ctx == nil {
		fmt.eprintfln("Error: Failed to create compiler context")
		os.exit(1)
	}

	// set no_exec flag to compile without executing
	mrb.ccontext_set_no_exec(mrb_ctx, true)
}

load_ruby_file :: proc(file_path, rel_path: string) -> []u8 {
	// compile Ruby file to bytecode
	source_bytes, read_err := os.read_entire_file(file_path, context.temp_allocator)
	if read_err != nil {
		fmt.eprintfln("Error reading Ruby file: %s", file_path)
		os.exit(1)
	}

	// set filename
	rel_path_cstr := strings.clone_to_cstring(rel_path, context.temp_allocator)
	mrb.ccontext_filename(mrb_state, mrb_ctx, rel_path_cstr)

	// compile without executing
	source_cstr := strings.clone_to_cstring(string(source_bytes), context.temp_allocator)
	result := mrb.load_string_cxt(mrb_state, source_cstr, rawptr(mrb_ctx))

	// extract bytecode
	rproc := mrb.RProc(uintptr(result.w))
	if rproc == nil {
		fmt.eprintfln("Error: Could not extract RProc from %s", rel_path)
		os.exit(1)
	}

	bin: rawptr
	bin_size: c.size_t
	dump_result := mrb.dump_irep(mrb_state, mrb.proc_irep(rproc), 0, &bin, &bin_size)

	if dump_result == 0 && bin != nil {
		// copy bytecode to owned slice
		bytecode := make([]u8, int(bin_size))
		copy_slice(bytecode, ([^]u8)(bin)[:bin_size])

		fmt.printfln("✓ Compiled %s (%d bytes bytecode)", rel_path, len(bytecode))
		return bytecode
	} else {
		fmt.eprintfln("Error: Failed to dump bytecode for %s", rel_path)
		os.exit(1)
	}
}

load_asset_file :: proc(file_path, rel_path: string) -> []u8 {
	file_bytes, read_err := os.read_entire_file(file_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Error reading file: %s", rel_path)
		os.exit(1)
	}
	fmt.printfln("✓ Included %s (%d bytes)", rel_path, len(file_bytes))
	return file_bytes
}

prepare_output_path :: proc(args: ^Args) -> string {
	output_path := args.output

	if args.web {
		// for web we need the basename of the source
		// and then it'll be the specified output path + that dir name

		// first make sure they didn't specify a file
		if os.is_file(output_path) {
			fmt.eprintfln("ERROR: Web package will be a directory, cannot specify a file.")
			os.exit(1)
		}

		// now extract the basename from the source
		info, basename_err := os.stat(args.source, context.temp_allocator)
		if basename_err != nil {
			fmt.eprintfln("ERROR: Specified source not found: %s", args.source)
			os.exit(1)
		}

		// make the dest dir
		output_path, _ = filepath.join({output_path, info.name}, context.temp_allocator)
		mkdir_err := make_directory_recursive(output_path)
		if mkdir_err != nil {
			fmt.eprintfln("ERROR: Unable to create output directory: %s", output_path)
			os.exit(1)
		}
	} else {
		if len(output_path) == 0 {
			// default to ./<dirname>.m9
			abs_source, _ := filepath.abs(args.source, context.temp_allocator)
			dir_name := filepath.base(abs_source)
			output_path = fmt.tprintf("%s.m9", dir_name)
		} else if os.is_dir(output_path) {
			// output is a directory, append input filename with .m9 extension
			abs_source, _ := filepath.abs(args.source, context.temp_allocator)
			dir_name := filepath.base(abs_source)
			output_path, _ = filepath.join(
				{output_path, fmt.tprintf("%s.m9", dir_name)},
				context.temp_allocator,
			)
		} else {
			// ensure parent directory exists for the cart file
			parent_dir := filepath.dir(output_path)
			if len(parent_dir) > 0 && parent_dir != "." {
				mkdir_err := make_directory_recursive(parent_dir)
				if mkdir_err != nil {
					fmt.eprintfln("ERROR: Unable to create parent directory: %s", parent_dir)
					os.exit(1)
				}
			}
		}
	}
	return output_path
}

find_files_to_include :: proc(args: ^Args, exclude_patterns: []string) -> [dynamic]string {
	// recursively list all files and filter by exclude patterns
	if !os.exists(args.source) {
		fmt.eprintfln("ERROR: Source directory '%s' does not exist", args.source)
		os.exit(1)
	}

	all_files := make([dynamic]string, context.temp_allocator)
	w := os.walker_create_path(args.source)
	defer os.walker_destroy(&w)
	for info in os.walker_walk(&w) {
		if info.type != .Directory {
			append(&all_files, strings.clone(info.fullpath, context.temp_allocator))
		}
	}
	fmt.printfln("\nFound %d total files", len(all_files))

	// filter out files that match exclude patterns (simple glob matching)
	filtered_files := make([dynamic]string, context.temp_allocator)

	for file_path in all_files {
		// make path relative to source for pattern matching
		rel_path, rel_err := filepath.rel(args.source, file_path, context.temp_allocator)
		if rel_err != .None { continue }

		// check if file matches any exclude pattern
		excluded := false
		for pattern in exclude_patterns {
			if matched, _ := filepath.match(pattern, rel_path); matched {
				fmt.printfln("Excluding %s (matches pattern %s)", rel_path, pattern)
				excluded = true
				break
			}
		}

		if !excluded {
			// file doesn't match any exclude pattern, keep it
			append(&filtered_files, file_path)
			// fmt.printfln("Including %s", rel_path)
		}
	}

	return filtered_files
}

load_package_metadata :: proc(path: string) -> (build: Package_Build) {
	metadata_path, _ := filepath.join({path, "metadata"}, context.temp_allocator)

	if os.exists(metadata_path) {
		data, read_err := os.read_entire_file(metadata_path, context.temp_allocator)
		if read_err != nil {
			fmt.eprintfln("Error reading metadata")
			os.exit(1)
		}

		parse_err := json.unmarshal(data, &build.metadata, .SJSON, context.temp_allocator)
		if parse_err != nil {
			fmt.eprintfln("Error parsing metadata: %v", parse_err)
			os.exit(1)
		}
	}

	return
}

calculate_file_sizes :: proc(path: string, metadata: ^Package_Build) {
	w := os.walker_create_path(path)
	defer os.walker_destroy(&w)
	for info in os.walker_walk(&w) {
		if info.type == .Directory { continue }
		metadata.total_size += info.size
		switch info.name {
		case "index.wasm":
			metadata.wasm_size = info.size
		case "cart.m9":
			metadata.rom_size = info.size
		}
	}
}

update_html_metadata :: proc(path: string, metadata: Package_Build) {
	html_file, _ := filepath.join({path, "index.html"}, context.temp_allocator)
	html_content, _ := os.read_entire_file(html_file, context.temp_allocator)
	html_str := string(html_content)

	// replace placeholders
	html_str, _ = strings.replace_all(html_str, "{{ TITLE }}", metadata.title, context.temp_allocator)
	html_str, _ = strings.replace_all(
		html_str,
		`const SAVE = "__NAME__"`,
		fmt.tprintf(`const SAVE = "m9:%s"`, metadata.name),
		context.temp_allocator,
	)
	html_str, _ = strings.replace_all(
		html_str,
		"const WASM_SIZE = -1",
		fmt.tprintf("const WASM_SIZE = %d", metadata.wasm_size),
		context.temp_allocator,
	)
	html_str, _ = strings.replace_all(
		html_str,
		"const ROM_SIZE = -1",
		fmt.tprintf("const ROM_SIZE = %d", metadata.rom_size),
		context.temp_allocator,
	)

	// write back to file
	write_err := os.write_entire_file(html_file, transmute([]u8)html_str)
	if write_err != nil {
		fmt.eprintfln("ERROR: Failed to write updated HTML")
		return
	}
}

@(private = "file")
make_directory_recursive :: proc(path: string) -> os.Error {
	if os.exists(path) {
		if os.is_dir(path) {
			return nil // directory already exists
		} else {
			return .Exist // path exists but is not a directory
		}
	}

	// get parent directory
	parent := filepath.dir(path)
	if len(parent) > 0 && parent != "." && parent != path {
		// recursively create parent directory
		parent_err := make_directory_recursive(parent)
		if parent_err != nil {
			return parent_err
		}
	}

	// create this directory
	return os.make_directory(path)
}
