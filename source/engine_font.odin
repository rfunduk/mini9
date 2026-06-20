package engine

import "core:strings"
import mrb "lib:mruby"
import rl "lib:raylib"

@(private = "file")
FontLoadData :: struct {
	file_type: string,
	bytes:     []u8,
	size:      i32,
	ruby_ptr:  mrb.Value,
}

@(private = "file")
deferred_fonts: [dynamic]FontLoadData

ruby_font_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		font_ptr := cast(^rl.Font)ptr

		// check if this points to built-in fonts in global memory
		builtin_start := rawptr(&g.fonts)
		builtin_end := rawptr(uintptr(builtin_start) + size_of(g.fonts))

		if font_is_atlas_backed(font_ptr) {
			// atlas owns texture — free raylib-allocated arrays only
			if font_ptr.recs != nil { rl.MemFree(rawptr(font_ptr.recs)) }
			if font_ptr.glyphs != nil { rl.MemFree(rawptr(font_ptr.glyphs)) }
		} else {
			rl.UnloadFont(font_ptr^)
		}

		// only free if it's not a built-in font
		if ptr < builtin_start || ptr >= builtin_end {
			mrb.free(state, ptr)
		}
	}
}

// helper to load a font from raw data - always uses memory
load_font :: proc(file_type: string, bytes: []u8, size: i32, ruby_obj: mrb.Value) -> (font: rl.Font) {
	file_type_cstr := strings.clone_to_cstring(file_type, context.temp_allocator)

	if file_type == ".png" {
		// for PNG bitmap fonts, LoadFontFromMemory doesn't handle them
		// we need to replicate what LoadFont does: load as image then use LoadFontFromImage
		image := rl.LoadImageFromMemory(file_type_cstr, raw_data(bytes), i32(len(bytes)))
		// use MAGENTA as key color and space (32) as first character, just like LoadFont does
		font = rl.LoadFontFromImage(image, rl.MAGENTA, 32)
		rl.UnloadImage(image)
	} else {
		font = rl.LoadFontFromMemory(file_type_cstr, raw_data(bytes), i32(len(bytes)), size, nil, 0)
	}

	rl.SetTextureFilter(font.texture, .POINT)

	font_ptr := mrb.alloc(g.mrb_state, font)
	mrb.data_init(ruby_obj, font_ptr, NATIVE_TO_MRUBY_TYPE[rl.Font])

	return
}

// create font from file path - reads file and calls memory version
create_font_from_path :: proc(path: string, size: i32) -> mrb.Value {
	// read the file using the utils wrapper that works on both native and web
	file_data, ok := read_entire_file(path, context.temp_allocator)
	if !ok {
		return mrb.raise_error(g.mrb_state, "RuntimeError", "Failed to read font file: %s", path)
	}

	// determine file type from extension (temp_allocator since create_font_from_memory clones if needed)
	dot := strings.last_index_byte(path, '.')
	file_type := strings.cut(path, dot)

	return create_font_from_memory(file_type, file_data, size)
}

// create font from memory
create_font_from_memory :: proc(file_type: string, bytes: []u8, size: i32) -> mrb.Value {
	font_class := mrb.class_get(g.mrb_state, "Font")
	ruby_obj := mrb.obj_new(g.mrb_state, font_class, 0, nil)

	if g.phase != .INIT {
		// if we're not in INIT phase (window initialized), load immediately
		load_font(file_type, bytes, size, ruby_obj)
	} else {
		// defer loading until after window is initialized
		mrb.data_init(ruby_obj, nil, NATIVE_TO_MRUBY_TYPE[rl.Font])

		// clone the bytes and file_type since we need to keep them around
		bytes_copy := make([]u8, len(bytes))
		copy(bytes_copy, bytes)

		append(
			&deferred_fonts,
			FontLoadData {
				file_type = strings.clone(file_type),
				bytes = bytes_copy,
				size = size,
				ruby_ptr = ruby_obj,
			},
		)
	}

	return ruby_obj
}

// create Ruby font object from pointer to raylib font (for built-in fonts in g.fonts)
create_font_from_raylib_ptr :: proc(font_ptr: ^rl.Font) -> mrb.Value {
	font_class := mrb.class_get(g.mrb_state, "Font")
	ruby_obj := mrb.obj_new(g.mrb_state, font_class, 0, nil)

	// point directly to the font in global memory
	mrb.data_init(ruby_obj, font_ptr, NATIVE_TO_MRUBY_TYPE[rl.Font])

	return ruby_obj
}

create_font :: proc {
	create_font_from_path,
	create_font_from_memory,
	create_font_from_raylib_ptr,
}

load_deferred_fonts :: proc() {
	// load built-in fonts into global storage first
	g.fonts.tiny = load_font_from_memory(".png", pixel_font_6_data[:])
	g.fonts.small = load_font_from_memory(".png", pixel_font_8_data[:])
	g.fonts.medium = load_font_from_memory(".png", pixel_font_11_data[:])
	g.fonts.large = load_font_from_memory(".png", pixel_font_15_data[:])

	queue_font_for_atlas(&g.fonts.tiny)
	queue_font_for_atlas(&g.fonts.small)
	queue_font_for_atlas(&g.fonts.medium)
	queue_font_for_atlas(&g.fonts.large)

	// load user-defined deferred fonts
	for &data in deferred_fonts {
		load_font(data.file_type, data.bytes, data.size, data.ruby_ptr)
		font_ptr := extract_native(rl.Font, data.ruby_ptr)
		if font_ptr != nil { queue_font_for_atlas(font_ptr) }
		delete(data.file_type)
		delete(data.bytes)
	}
	clear(&deferred_fonts)
}

// load font from memory (Odin version, doesn't create Ruby object)
load_font_from_memory :: proc(file_type: string, bytes: []u8, size: i32 = 0) -> rl.Font {
	file_type_cstr := strings.clone_to_cstring(file_type, context.temp_allocator)
	font: rl.Font

	if file_type == ".png" {
		image := rl.LoadImageFromMemory(file_type_cstr, raw_data(bytes), i32(len(bytes)))
		font = rl.LoadFontFromImage(image, rl.MAGENTA, 32)
		rl.UnloadImage(image)
	} else {
		font = rl.LoadFontFromMemory(file_type_cstr, raw_data(bytes), i32(len(bytes)), size, nil, 0)
	}

	rl.SetTextureFilter(font.texture, .POINT)
	return font
}

// RUBY FUNCTION: font(path, size=nil) -> returns Font object
// @engine_method: name="font", aspec=ARGS_ARG(1,1)
ruby_font :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val, size_val: mrb.Value
	argc := mrb.get_args(state, "o|o", &path_val, &size_val)

	// convert path to string
	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := strings.clone_from_cstring(c_str, context.temp_allocator)

	// check if size is needed based on file type
	size: i32 = 0
	if !strings.has_suffix(path, ".png") {
		// TTF/OTF requires size
		if argc < 2 || size_val == mrb.NIL {
			return mrb.raise_error(
				state,
				"ArgumentError",
				"font() requires size parameter for TTF/OTF files: %s",
				path,
			)
		}
		size = i32(mrb.to_int(size_val))
	}

	return create_font(path, size)
}

ruby_font_get_name :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	// TODO rename this to, and return the, path
	return mrb.str_new_cstr(state, "font")
}

ruby_font_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	font := extract_native(rl.Font, self)
	return mrb.boxing_int_value(state, font == nil ? 0 : font.baseSize)
}

setup_font :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Font")

	mrb.define_method(g.mrb_state, c, "name", cast(rawptr)ruby_font_get_name, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_font_get_size, mrb.ARGS_NONE)

	mrb.define_const(g.mrb_state, c, "TINY", create_font(&g.fonts.tiny))
	mrb.define_const(g.mrb_state, c, "SMALL", create_font(&g.fonts.small))
	mrb.define_const(g.mrb_state, c, "MEDIUM", create_font(&g.fonts.medium))
	mrb.define_const(g.mrb_state, c, "LARGE", create_font(&g.fonts.large))
}

cleanup_font :: proc() {
	delete(deferred_fonts)
}
