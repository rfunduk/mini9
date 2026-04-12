package engine

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
	path:   string,
	colors: [dynamic]PaletteColor,
}

ruby_palette_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		pal := cast(^Palette)ptr
		free_palette_storage(pal)
		delete(pal.path)
		mrb.free(state, ptr)
	}
}

@(private = "file")
free_palette_storage :: proc(pal: ^Palette) {
	if pal.colors != nil {
		for &pc in pal.colors {
			delete(pc.name)
		}
		delete(pal.colors)
		pal.colors = nil
	}
}

@(private = "file")
parse_palette_gpl :: proc(data: []byte, pal: ^Palette) {
	palette_str := string(data[:])
	lines := strings.split_lines(palette_str, context.temp_allocator)

	for &line in lines {
		line = strings.trim_space(line)
		if line == "" || strings.has_prefix(line, "#") || strings.has_prefix(line, "GIMP") { continue }

		parts := strings.fields(line, context.temp_allocator)
		if len(parts) < 4 { continue }

		r_val, r_ok := strconv.parse_int(parts[0])
		g_val, g_ok := strconv.parse_int(parts[1])
		b_val, b_ok := strconv.parse_int(parts[2])
		if !(r_ok && g_ok && b_ok) { continue }

		// strings.to_lower allocates from context.allocator (heap) — owned by Palette
		color_name := strings.to_lower(parts[3])
		color := rl.Color{u8(r_val), u8(g_val), u8(b_val), 255}
		append(&pal.colors, PaletteColor{color_name, create_color(color)})
	}
}

palette_from_filedata :: proc(path: string, data: []u8) -> mrb.Value {
	file_ext := strings.to_lower(slashpath.ext(path), context.temp_allocator)
	if file_ext != ".gpl" {
		return mrb.raise_error(g.mrb_state, "RuntimeError", "Unknown palette file type: %s", file_ext)
	}

	palette_class := mrb.class_get(g.mrb_state, "Palette")
	ruby_obj := mrb.obj_new(g.mrb_state, palette_class, 0, nil)

	pal := mrb.alloc(g.mrb_state, Palette {
		path = strings.clone(path),
		colors = make([dynamic]PaletteColor),
	})

	parse_palette_gpl(data, pal)
	mrb.data_init(ruby_obj, pal, NATIVE_TO_MRUBY_TYPE[Palette])

	// Color values are only referenced from the native slice until
	// install_color_methods captures them in singleton method closures.
	// Protect them across the funcall, then drop the temporary roots.
	for pc in pal.colors { mrb.gc_register(g.mrb_state, pc.color) }
	mrb.funcall(g.mrb_state, ruby_obj, "install_color_methods", 0)
	for pc in pal.colors { mrb.gc_unregister(g.mrb_state, pc.color) }

	return ruby_obj
}

create_palette :: proc(path: string) -> mrb.Value {
	file_data, ok := read_entire_file(path)
	if !ok {
		return mrb.raise_error(g.mrb_state, "RuntimeError", "Could not load palette file: %s", path)
	}
	defer delete(file_data)
	return palette_from_filedata(path, file_data)
}

// RUBY FUNCTION: palette(path) -> returns Palette object
// @engine_method: name="palette", arity=1
ruby_palette :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val: mrb.Value
	mrb.get_args(state, "o", &path_val)

	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	return create_palette(string(c_str))
}

ruby_palette_get :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	name_or_index: mrb.Value
	mrb.get_args(state, "o", &name_or_index)

	pal := extract_native(Palette, self)
	if pal == nil { return mrb.NIL }

	if mrb.integer_p(name_or_index) {
		idx := int(mrb.integer(name_or_index))
		if idx < 0 || idx >= len(pal.colors) { return mrb.NIL }
		return pal.colors[idx].color
	}

	str_obj := mrb.obj_as_string(state, name_or_index)
	name_str := string(mrb.str_to_cstr(state, str_obj))
	for pc in pal.colors {
		if pc.name == name_str { return pc.color }
	}
	return mrb.NIL
}

ruby_palette_path :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pal := extract_native(Palette, self)
	if pal == nil { return mrb.NIL }
	return mrb.str_new_cstr(state, strings.clone_to_cstring(pal.path, context.temp_allocator))
}

ruby_palette_count :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pal := extract_native(Palette, self)
	if pal == nil { return mrb.boxing_int_value(state, 0) }
	return mrb.boxing_int_value(state, i32(len(pal.colors)))
}

ruby_palette_colors :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pal := extract_native(Palette, self)
	if pal == nil { return mrb.ary_new(state) }
	arr := mrb.ary_new(state)
	for pc in pal.colors {
		mrb.ary_push(state, arr, pc.color)
	}
	return arr
}

// Returns Array of [Symbol, Color] pairs. Used by palette.rb to (re)install
// the .red / .blue / etc. singleton accessors.
ruby_palette_color_pairs :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pal := extract_native(Palette, self)
	if pal == nil { return mrb.ary_new(state) }
	arr := mrb.ary_new(state)
	for pc in pal.colors {
		pair := mrb.ary_new(state)
		name_cstr := strings.clone_to_cstring(pc.name, context.temp_allocator)
		sym := mrb.symbol_value(mrb.intern_cstr(state, name_cstr))
		mrb.ary_push(state, pair, sym)
		mrb.ary_push(state, pair, pc.color)
		mrb.ary_push(state, arr, pair)
	}
	return arr
}

// Returns a deep-copied independent Palette. Used by preamble to give `P`
// its own backing so user-driven `P.replace(...)` calls can't mutate
// Palette::DEFAULT.
ruby_palette_dup :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	src := extract_native(Palette, self)
	if src == nil { return mrb.NIL }

	palette_class := mrb.class_get(state, "Palette")
	new_obj := mrb.obj_new(state, palette_class, 0, nil)

	new_pal := mrb.alloc(state, Palette {
		path = strings.clone(src.path),
		colors = make([dynamic]PaletteColor),
	})
	for pc in src.colors {
		src_color := extract_native(rl.Color, pc.color)
		new_color := create_color(src_color^)
		append(&new_pal.colors, PaletteColor{strings.clone(pc.name), new_color})
	}

	mrb.data_init(new_obj, new_pal, NATIVE_TO_MRUBY_TYPE[Palette])

	for pc in new_pal.colors { mrb.gc_register(state, pc.color) }
	mrb.funcall(state, new_obj, "install_color_methods", 0)
	for pc in new_pal.colors { mrb.gc_unregister(state, pc.color) }

	return new_obj
}

// Replace this palette's storage with a deep copy of `other`'s, then
// reinstall the singleton accessors. Color values are freshly allocated so
// the two palettes have fully independent ownership after the call.
ruby_palette_do_replace :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other_val: mrb.Value
	mrb.get_args(state, "o", &other_val)

	self_pal := extract_native(Palette, self)
	other_pal := extract_native(Palette, other_val)
	if self_pal == nil || other_pal == nil { return self }

	// Self-replace is a no-op. Without this guard, freeing self.colors
	// would also wipe other.colors (same pointer) and the copy loop would
	// see an empty source.
	if self_pal == other_pal { return self }

	// Old singleton methods still root the OLD color values via closures —
	// safe to free the slice and rebuild it before tearing them down.
	free_palette_storage(self_pal)
	delete(self_pal.path)

	self_pal.path = strings.clone(other_pal.path)
	self_pal.colors = make([dynamic]PaletteColor)
	for pc in other_pal.colors {
		other_color := extract_native(rl.Color, pc.color)
		new_color := create_color(other_color^)
		append(&self_pal.colors, PaletteColor{strings.clone(pc.name), new_color})
	}

	// Same protection rationale as palette_from_filedata.
	for pc in self_pal.colors { mrb.gc_register(state, pc.color) }
	mrb.funcall(state, self, "uninstall_color_methods", 0)
	mrb.funcall(state, self, "install_color_methods", 0)
	for pc in self_pal.colors { mrb.gc_unregister(state, pc.color) }

	return self
}

setup_palette :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Palette")
	mrb.define_method(g.mrb_state, c, "[]", cast(rawptr)ruby_palette_get, 1)
	mrb.define_method(g.mrb_state, c, "path", cast(rawptr)ruby_palette_path, 0)
	mrb.define_method(g.mrb_state, c, "count", cast(rawptr)ruby_palette_count, 0)
	mrb.define_method(g.mrb_state, c, "colors", cast(rawptr)ruby_palette_colors, 0)
	mrb.define_method(g.mrb_state, c, "__color_pairs", cast(rawptr)ruby_palette_color_pairs, 0)
	mrb.define_method(g.mrb_state, c, "__do_replace", cast(rawptr)ruby_palette_do_replace, 1)
	mrb.define_method(g.mrb_state, c, "dup", cast(rawptr)ruby_palette_dup, 0)
	mrb.define_const(g.mrb_state, c, "DEFAULT", palette_from_filedata("default_palette.gpl", palette_data))
}
