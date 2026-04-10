package engine

import "core:fmt"
import "core:path/slashpath"
import "core:strconv"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

PaletteColor :: struct {
	name:  string,
	color: mrb.Value,
}

Palette :: struct {
	type:   string,
	count:  u8,
	colors: [dynamic]PaletteColor,
}

ruby_palette_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		pal := cast(^Palette)ptr
		if pal.colors != nil {
			for &pc in pal.colors {
				delete(pc.name)
			}
			delete(pal.colors)
		}
		mrb.free(state, ptr)
	}
}

create_palette :: proc(path: string) -> mrb.Value {
	path_str := string(path)
	file_data, ok := read_entire_file(path_str)
	if !ok {
		return ruby_raise("RuntimeError", "Could not load palette file: %s", path_str)
	}
	defer delete(file_data)

	return palette_from_filedata(path, file_data)
}

palette_from_filedata :: proc(path: string, data: []u8) -> mrb.Value {
	palette_class := mrb.class_get(g.mrb_state, "Palette")
	ruby_obj := mrb.obj_new(g.mrb_state, palette_class, 0, nil)

	// get file extension
	file_ext := strings.to_lower(slashpath.ext(path), context.temp_allocator)

	palette_ptr := ruby_allocate(Palette, Palette{type = file_ext, colors = make([dynamic]PaletteColor)})

	// set @path instance variable
	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	mrb.data_init(ruby_obj, palette_ptr, NATIVE_TO_MRUBY_TYPE[Palette])

	switch file_ext {
	case ".gpl":
		parse_palette_gpl(data, palette_ptr)
	case:
		return ruby_raise("RuntimeError", "Unknown palette file type: %s", file_ext)
	}

	// set @count instance variable
	count_sym := mrb.intern_cstr(g.mrb_state, "@count")
	mrb.iv_set(
		g.mrb_state,
		ruby_obj,
		count_sym,
		mrb.boxing_int_value(g.mrb_state, i32(len(palette_ptr.colors))),
	)

	color_names := mrb.ary_new(g.mrb_state)
	colors_array := mrb.ary_new(g.mrb_state)
	for pc in palette_ptr.colors {
		name_sym := mrb.intern_cstr(g.mrb_state, fmt.ctprintf("@%s", pc.name))
		mrb.iv_set(g.mrb_state, ruby_obj, name_sym, pc.color)
		mrb.ary_push(g.mrb_state, colors_array, pc.color)
		mrb.ary_push(
			g.mrb_state,
			color_names,
			mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(pc.name, context.temp_allocator)),
		)
	}
	colors_sym := mrb.intern_cstr(g.mrb_state, "@colors")
	mrb.iv_set(g.mrb_state, ruby_obj, colors_sym, colors_array)

	mrb.funcall_argv(
		g.mrb_state,
		ruby_obj,
		mrb.intern_cstr(g.mrb_state, "setup"),
		2,
		&[2]mrb.Value{color_names, colors_array},
	)

	return ruby_obj
}

// RUBY FUNCTION: palette(path=nil) -> returns Palette object
// @engine_method: name="palette", arity=-1
ruby_palette :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val: mrb.Value
	mrb.get_args(state, "o", &path_val)

	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := string(c_str)

	result := create_palette(path)
	return result
}

parse_palette_gpl :: proc(data: []byte, p: ^Palette) {
	palette_str := string(data[:])
	lines := strings.split_lines(palette_str, context.temp_allocator)

	for &line in lines {
		line = strings.trim_space(line)
		if line == "" || strings.has_prefix(line, "#") || strings.has_prefix(line, "GIMP") {
			continue
		}

		parts := strings.fields(line, context.temp_allocator)

		if len(parts) >= 4 {
			r_val, r_ok := strconv.parse_int(parts[0])
			g_val, g_ok := strconv.parse_int(parts[1])
			b_val, b_ok := strconv.parse_int(parts[2])

			if r_ok && g_ok && b_ok {
				// TODO it's actually all remaining parts
				color_name := strings.to_lower(parts[3])
				color := rl.Color{u8(r_val), u8(g_val), u8(b_val), 255}
				append(&p.colors, PaletteColor{color_name, create_color(color)})
			}
		}
	}
}

ruby_palette_get_color :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	name_or_index: mrb.Value
	mrb.get_args(state, "o", &name_or_index)
	palette := extract_native(Palette, self)

	if mrb.integer_p(name_or_index) {
		index := int(mrb.integer(name_or_index))
		if index < 0 || index >= len(palette.colors) { return mrb.NIL }
		return palette.colors[index].color
	}

	str_obj := mrb.obj_as_string(state, name_or_index)
	c_str := mrb.str_to_cstr(state, str_obj)
	name_str := string(c_str)

	// not an index, try names
	for color in palette.colors {
		if color.name == name_str { return color.color }
	}

	return mrb.NIL
}

setup_palette :: proc() {
	c := create_data_class("Palette")
	mrb.define_method(g.mrb_state, c, "[]", cast(rawptr)ruby_palette_get_color, 1)
	mrb.define_const(g.mrb_state, c, "DEFAULT", palette_from_filedata("default_palette.gpl", palette_data))
}
