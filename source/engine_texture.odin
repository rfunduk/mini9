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

Texture_Kind :: enum {
	ATLAS, // tex points at the shared atlas; tex_origin/w/h locate sub-image
	STANDALONE, // tex is owned by this Texture
}

Texture :: struct {
	tex:        rl.Texture2D,
	tex_origin: rl.Vector2, // top-left within tex (0,0 for STANDALONE)
	w, h:       f32, // logical size of this texture (NOT atlas size)
	kind:       Texture_Kind,
	status:     Texture_Load_Status,
}

@(private = "file")
Texture_Load_Data :: struct {
	path:     cstring,
	ruby_ptr: mrb.Value,
}

@(private = "file")
deferred_textures: [dynamic]Texture_Load_Data

ruby_texture_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		texture_ptr := cast(^Texture)ptr
		texture_ptr.status = .UNLOADED
		// only STANDALONE owns its texture; ATLAS-kind shares the atlas texture
		if texture_ptr.kind == .STANDALONE { rl.UnloadTexture(texture_ptr.tex) }
		mrb.free(state, ptr)
	}
}

// load_texture_standalone — used after init phase OR for atlas spillover.
// Decodes file → texture, assigns to Texture struct as STANDALONE.
load_texture_standalone :: proc(path: cstring, ruby_obj: mrb.Value) -> ^Texture {
	path_str := string(path)
	file_data, ok := read_entire_file(path_str)
	if !ok {
		mrb.raise_error(g.mrb_state, "RuntimeError", "Could not load texture file: %s", path_str)
		return nil
	}
	defer delete(file_data)

	file_ext_cstr := strings.clone_to_cstring(slashpath.ext(path_str), context.temp_allocator)
	image := rl.LoadImageFromMemory(file_ext_cstr, raw_data(file_data), i32(len(file_data)))
	defer rl.UnloadImage(image)

	tex := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(tex, .POINT)

	texture_ptr := extract_native(Texture, ruby_obj)
	texture_ptr.kind = .STANDALONE
	texture_ptr.tex = tex
	texture_ptr.tex_origin = {0, 0}
	texture_ptr.w = f32(image.width)
	texture_ptr.h = f32(image.height)
	texture_ptr.status = .LOADED

	return texture_ptr
}

// load_texture_for_atlas — decodes image during init phase, queues for atlas
// pack. Image is owned by atlas module until pack_atlas runs.
load_texture_for_atlas :: proc(path: cstring, ruby_obj: mrb.Value) {
	path_str := string(path)
	file_data, ok := read_entire_file(path_str)
	if !ok {
		mrb.raise_error(g.mrb_state, "RuntimeError", "Could not load texture file: %s", path_str)
		return
	}
	defer delete(file_data)

	file_ext_cstr := strings.clone_to_cstring(slashpath.ext(path_str), context.temp_allocator)
	image := rl.LoadImageFromMemory(file_ext_cstr, raw_data(file_data), i32(len(file_data)))
	// note: do NOT UnloadImage here — atlas owns it until pack_atlas runs

	texture_ptr := extract_native(Texture, ruby_obj)
	if texture_ptr != nil {
		texture_ptr.kind = .ATLAS
		texture_ptr.w = f32(image.width)
		texture_ptr.h = f32(image.height)
		texture_ptr.status = .PENDING
	}

	queue_texture_for_atlas(ruby_obj, image)
}

create_texture :: proc(path: string) -> mrb.Value {
	texture_class := mrb.class_get(g.mrb_state, "Texture")
	ruby_obj := mrb.obj_new(g.mrb_state, texture_class, 0, nil)

	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	texture_ptr := mrb.alloc(g.mrb_state, Texture{})
	mrb.data_init(ruby_obj, texture_ptr, NATIVE_TO_MRUBY_TYPE[Texture])

	if g.phase == .UPDATE {
		// post-init lazy load → standalone (atlas already built)
		cpath := strings.clone_to_cstring(path, context.temp_allocator)
		load_texture_standalone(cpath, ruby_obj)
	} else {
		// during init: defer; load_deferred_textures will route to atlas
		append(&deferred_textures, Texture_Load_Data{strings.clone_to_cstring(path), ruby_obj})
	}

	return ruby_obj
}

load_deferred_textures :: proc() {
	for &data in deferred_textures {
		load_texture_for_atlas(data.path, data.ruby_ptr)
		delete(data.path)
	}
	clear(&deferred_textures)
	// pack_atlas() is called from engine.odin after both fonts AND textures
	// are loaded, so they share one atlas pass.
}

// RUBY FUNCTION: texture(path) -> returns Texture object
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
	if texture == nil { return mrb.NIL }
	return create_vector2({texture.w, texture.h})
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

	if argc == 2 {
		val := mrb.kwarg(state, kwargs, sym.clip)
		if val != mrb.NIL { did_clip = _clip(val, pos) }
	}

	source := rl.Rectangle{texture.tex_origin.x, texture.tex_origin.y, texture.w, texture.h}
	dest := rl.Rectangle{pos.x, pos.y, texture.w, texture.h}
	rl.DrawTexturePro(texture.tex, source, dest, {0, 0}, 0, rl.WHITE)

	if did_clip { rl.EndScissorMode() }

	return self
}

setup_texture :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Texture")
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_texture_get_size, 0)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_texture_draw, 1)
}

cleanup_texture :: proc() {
	delete(deferred_textures)
}
