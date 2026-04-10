package engine

import lin "core:math/linalg"
import "core:path/slashpath"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

Texture_Load_Status :: enum {
	PENDING,
	LOADED,
	UNLOADED,
}

Texture :: struct {
	tex:    rl.Texture2D,
	status: Texture_Load_Status,
}

Texture_Load_Data :: struct {
	path:     cstring,
	ruby_ptr: mrb.Value,
}

ruby_texture_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		texture_ptr := cast(^Texture)ptr
		texture_ptr.status = .UNLOADED
		rl.UnloadTexture(texture_ptr.tex)
		mrb.free(state, ptr)
	}
}

load_texture :: proc(path: cstring, ruby_obj: mrb.Value) -> ^Texture {
	// read file data into memory first
	path_str := string(path)
	file_data, ok := read_entire_file(path_str)
	if !ok {
		ruby_raise("RuntimeError", "Could not load texture file: %s", path_str)
		return nil
	}
	defer delete(file_data)

	// get file extension for LoadImageFromMemory
	file_ext_cstr := strings.clone_to_cstring(slashpath.ext(path_str), context.temp_allocator)

	// load image from memory data
	image := rl.LoadImageFromMemory(file_ext_cstr, raw_data(file_data), i32(len(file_data)))
	defer rl.UnloadImage(image)

	// convert image to texture
	tex := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(tex, .POINT)

	texture_ptr := extract_native(Texture, ruby_obj)
	texture_ptr.tex = tex
	texture_ptr.status = .LOADED

	return texture_ptr
}

create_texture :: proc(path: string) -> mrb.Value {
	texture_class := mrb.class_get(g.mrb_state, "Texture")
	ruby_obj := mrb.obj_new(g.mrb_state, texture_class, 0, nil)

	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	texture_ptr := ruby_allocate(Texture, Texture{})
	mrb.data_init(ruby_obj, texture_ptr, NATIVE_TO_MRUBY_TYPE[Texture])

	// if we're in UPDATE phase (window initialized), load immediately
	if g.phase == .UPDATE {
		cpath := strings.clone_to_cstring(path, context.temp_allocator)
		load_texture(cpath, ruby_obj)
	} else {
		// we still need to set a pointer to a Texture_Ruby, but it's a null pointer
		// defer loading the texture until after window is initialized
		append(&g.deferred_textures, Texture_Load_Data{strings.clone_to_cstring(path), ruby_obj})
	}

	return ruby_obj
}

load_deferred_textures :: proc() {
	for &data in g.deferred_textures {
		load_texture(data.path, data.ruby_ptr)
		delete(data.path) // free the cloned cstring
	}
	clear(&g.deferred_textures)
}

// RUBY FUNCTION: texture(path, size=nil) -> returns Texture object
// @engine_method: name="texture", arity=1
ruby_texture :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val: mrb.Value
	mrb.get_args(state, "o", &path_val)

	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := string(c_str)

	result := create_texture(path)
	return result
}

ruby_texture_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	texture := extract_native(Texture, self)
	tex := texture.tex
	if texture != nil {
		return create_vector2({f32(tex.width), f32(tex.height)})
	} else {
		return mrb.NIL
	}
}

ruby_texture_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &pos_val, &kwargs)

	texture := extract_native(Texture, self)
	if texture == nil || texture.status != .LOADED { return mrb.NIL }

	pos_ptr := extract_native(rl.Vector2, pos_val)
	if pos_ptr == nil { return mrb.NIL }

	pos := lin.floor(pos_ptr^)
	did_clip := false

	if argc == 2 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)
		if "clip" in hash { did_clip = _clip(hash["clip"], pos) }
	}

	tex := texture.tex
	rl.DrawTextureV(tex, pos, rl.WHITE)

	if did_clip { rl.EndScissorMode() }

	return self
}

setup_texture :: proc() {
	c := create_data_class("Texture")
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_texture_get_size, 0)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_texture_draw, 1)
}
