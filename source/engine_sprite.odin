package engine

import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

Sprite :: struct {
	atlas:    ^Texture,
	size:     rl.Vector2,
	offset:   rl.Vector2,
	scale:    rl.Vector2,
	rotation: f32,
	frame:    uint,
	frames:   uint,
	fliph:    bool,
	flipv:    bool,
}

ruby_sprite_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

// RUBY FUNCTION: sprite(texture, size: nil, frame: 0, frames: 1, fliph: false, flipv: false) -> returns Sprite object
// @engine_method: name="sprite", arity=1
ruby_sprite :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	atlas_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &atlas_val, &kwargs)

	atlas := extract_native(Texture, atlas_val)
	found_atlas: bool = atlas != nil && atlas.status != .UNLOADED

	size := rl.Vector2{-1, -1}
	frame: uint = 0
	frames: uint = 0 // 0 means auto-calculate when needed
	fliph := false
	flipv := false
	rotation: f32 = 0
	offset := rl.Vector2{0, 0}
	scale := rl.Vector2{1, 1}

	if argc == 2 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, g.sym.size)
		if val != mrb.NIL { size = extract_native(rl.Vector2, val)^ }
		val = mrb.kwarg(state, kwargs, g.sym.frame)
		if val != mrb.NIL { frame = uint(mrb.integer(val)) }
		val = mrb.kwarg(state, kwargs, g.sym.frames)
		if val != mrb.NIL { frames = uint(mrb.integer(val)) }
		val = mrb.kwarg(state, kwargs, g.sym.fliph)
		if val != mrb.NIL { fliph = mrb.boolean(val) }
		val = mrb.kwarg(state, kwargs, g.sym.flipv)
		if val != mrb.NIL { flipv = mrb.boolean(val) }
		val = mrb.kwarg(state, kwargs, g.sym.rotation)
		if val != mrb.NIL { rotation = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, g.sym.offset)
		if val != mrb.NIL { offset = extract_native(rl.Vector2, val)^ }
		val = mrb.kwarg(state, kwargs, g.sym.scale)
		if val != mrb.NIL { scale = extract_native(rl.Vector2, val)^ }
		val = mrb.kwarg(state, kwargs, g.sym.atlas)
		if val != mrb.NIL {
			atlas = extract_native(Texture, val)
			if atlas != nil { found_atlas = true }
		}
	}

	if !found_atlas {
		return mrb.raise_error(state, "ArgumentError", "Sprite requires a texture to use as atlas")
	}

	sprite_obj := create_sprite(
		Sprite {
			atlas = atlas,
			size = size,
			frame = frame,
			frames = frames,
			fliph = fliph,
			flipv = flipv,
			rotation = rotation,
			offset = offset,
			scale = scale,
		},
	)

	// only set @atlas since it's referenced in Ruby code (e.g. to_s method)
	atlas_sym := mrb.intern_cstr(state, "@atlas")
	mrb.iv_set(state, sprite_obj, atlas_sym, atlas_val)

	return sprite_obj
}

create_sprite :: proc(s: Sprite) -> mrb.Value {
	context = global_context

	spr_ptr := mrb.alloc(g.mrb_state, s)

	sprite_class := mrb.class_get(g.mrb_state, "Sprite")
	ruby_obj := mrb.obj_new(g.mrb_state, sprite_class, 0, nil)

	mrb.data_init(ruby_obj, spr_ptr, NATIVE_TO_MRUBY_TYPE[Sprite])

	return ruby_obj
}

// get sprite frame count, auto-calculating if needed
get_sprite_frames :: proc(sprite: ^Sprite) -> uint {
	if sprite.frames == 0 && sprite.size.x > 0 && sprite.size.y > 0 && sprite.atlas.status == .LOADED {
		tex := sprite.atlas.tex
		cols := int(f32(tex.width) / sprite.size.x)
		rows := int(f32(tex.height) / sprite.size.y)
		if cols > 0 && rows > 0 {
			sprite.frames = uint(cols * rows)
		} else {
			sprite.frames = 1
		}
	}
	return sprite.frames == 0 ? 1 : sprite.frames
}

// RUBY METHOD: sprite.size -> gets sprite frame size
ruby_sprite_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return create_vector2(sprite.size)
}

// RUBY METHOD: sprite.frame -> gets sprite frame index
ruby_sprite_get_frame :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, i32(sprite.frame))
}

// RUBY METHOD: sprite.frames -> gets sprite frame count
ruby_sprite_get_frames :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, i32(get_sprite_frames(sprite)))
}

// RUBY METHOD: sprite.fliph -> gets horizontal flip flag
ruby_sprite_get_fliph :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return sprite.fliph ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: sprite.flipv -> gets vertical flip flag
ruby_sprite_get_flipv :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return sprite.flipv ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: sprite.rotation -> gets rotation in radians
ruby_sprite_get_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(sprite.rotation))
}

// RUBY METHOD: sprite.offset -> gets offset vector
ruby_sprite_get_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return create_vector2(sprite.offset)
}

// RUBY METHOD: sprite.scale -> gets scale vector
ruby_sprite_get_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return create_vector2(sprite.scale)
}

// RUBY METHOD: sprite.rotation_degrees -> gets rotation in degrees
ruby_sprite_get_rotation_degrees :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(sprite.rotation * 180.0 / math.PI))
}

// RUBY METHOD: sprite.set_size(v2) -> sets sprite frame size
ruby_sprite_set_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	size_val: mrb.Value
	mrb.get_args(state, "o", &size_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	size_ptr := extract_native(rl.Vector2, size_val)
	if size_ptr != nil { sprite.size = size_ptr^ }

	return size_val
}

// RUBY METHOD: sprite.set_frame(n) -> sets sprite frame index with wrapping
ruby_sprite_set_frame :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	frame_val: mrb.Value
	mrb.get_args(state, "o", &frame_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	new_frame := uint(mrb.integer(frame_val))

	frames := get_sprite_frames(sprite)
	if frames > 0 && new_frame >= frames {
		sprite.frame = new_frame % frames
	} else {
		sprite.frame = new_frame
	}

	return frame_val
}

// RUBY METHOD: sprite._set_flip(fliph, flipv) -> sets sprite flip flags
ruby_sprite_set_flip :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	fliph_val, flipv_val: mrb.Value
	mrb.get_args(state, "oo", &fliph_val, &flipv_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	if fliph_val != mrb.NIL { sprite.fliph = mrb.boolean(fliph_val) }
	if flipv_val != mrb.NIL { sprite.flipv = mrb.boolean(flipv_val) }

	return self
}

// RUBY METHOD: sprite.rotation=(angle) -> sets rotation in radians
ruby_sprite_set_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	rotation_val: mrb.Value
	mrb.get_args(state, "o", &rotation_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	sprite.rotation = f32(mrb.to_f64(rotation_val))

	return rotation_val
}

// RUBY METHOD: sprite.offset=(v2) -> sets offset vector
ruby_sprite_set_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	offset_val: mrb.Value
	mrb.get_args(state, "o", &offset_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	offset_ptr := extract_native(rl.Vector2, offset_val)
	if offset_ptr != nil { sprite.offset = offset_ptr^ }

	return offset_val
}

// RUBY METHOD: sprite.scale=(v2) -> sets scale vector
ruby_sprite_set_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	scale_val: mrb.Value
	mrb.get_args(state, "o", &scale_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	scale_ptr := extract_native(rl.Vector2, scale_val)
	if scale_ptr != nil { sprite.scale = scale_ptr^ }

	return scale_val
}

// RUBY METHOD: sprite.rotation_degrees=(angle) -> sets rotation in degrees
ruby_sprite_set_rotation_degrees :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	rotation_val: mrb.Value
	mrb.get_args(state, "o", &rotation_val)

	sprite := extract_native(Sprite, self)
	if sprite == nil { return mrb.NIL }

	sprite.rotation = f32(mrb.to_f64(rotation_val) * math.PI / 180.0)

	return rotation_val
}

ruby_sprite_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &pos_val, &kwargs)

	sprite := extract_native(Sprite, self)
	if sprite == nil || sprite.atlas == nil || sprite.atlas.status != .LOADED {
		return mrb.NIL
	}

	pos_ptr := extract_native(rl.Vector2, pos_val)
	if pos_ptr == nil { return mrb.NIL }

	pos := lin.floor(pos_ptr^)
	did_clip := false

	if argc == 2 {
		val := mrb.kwarg(state, kwargs, g.sym.clip)
		if val != mrb.NIL { did_clip = _clip(val, pos) }
	}

	// calculate source rectangle from sprite settings
	tex := sprite.atlas.tex
	frame_width := sprite.size.x > 0 ? sprite.size.x : f32(tex.width)
	frame_height := sprite.size.y > 0 ? sprite.size.y : f32(tex.height)

	// calculate frame position in atlas
	cols := int(f32(tex.width) / frame_width)
	if cols == 0 { cols = 1 }

	// calculate position based on frame index within the grid
	col := int(sprite.frame) % cols
	row := int(sprite.frame) / cols

	frame_x := f32(col) * frame_width
	frame_y := f32(row) * frame_height

	// source rectangle (handle flipping)
	source := rl.Rectangle {
		x      = math.floor(frame_x),
		y      = math.floor(frame_y),
		width  = math.floor(sprite.fliph ? -frame_width : frame_width),
		height = math.floor(sprite.flipv ? -frame_height : frame_height),
	}

	dest := rl.Rectangle {
		x      = pos.x,
		y      = pos.y,
		width  = math.floor(abs(frame_width) * sprite.scale.x),
		height = math.floor(abs(frame_height) * sprite.scale.y),
	}

	rl.DrawTexturePro(tex, source, dest, -sprite.offset, sprite.rotation * 180.0 / math.PI, rl.WHITE)

	if did_clip { rl.EndScissorMode() }

	return self
}

setup_sprite :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Sprite")

	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_sprite_get_size, 0)
	mrb.define_method(g.mrb_state, c, "size=", cast(rawptr)ruby_sprite_set_size, 1)
	mrb.define_method(g.mrb_state, c, "frame", cast(rawptr)ruby_sprite_get_frame, 0)
	mrb.define_method(g.mrb_state, c, "frame=", cast(rawptr)ruby_sprite_set_frame, 1)
	mrb.define_method(g.mrb_state, c, "frames", cast(rawptr)ruby_sprite_get_frames, 0)
	mrb.define_method(g.mrb_state, c, "fliph", cast(rawptr)ruby_sprite_get_fliph, 0)
	mrb.define_method(g.mrb_state, c, "flipv", cast(rawptr)ruby_sprite_get_flipv, 0)
	mrb.define_method(g.mrb_state, c, "_set_flip", cast(rawptr)ruby_sprite_set_flip, 2)
	mrb.define_method(g.mrb_state, c, "rotation", cast(rawptr)ruby_sprite_get_rotation, 0)
	mrb.define_method(g.mrb_state, c, "rotation=", cast(rawptr)ruby_sprite_set_rotation, 1)
	mrb.define_method(g.mrb_state, c, "rotation_degrees", cast(rawptr)ruby_sprite_get_rotation_degrees, 0)
	mrb.define_method(g.mrb_state, c, "rotation_degrees=", cast(rawptr)ruby_sprite_set_rotation_degrees, 1)
	mrb.define_method(g.mrb_state, c, "offset", cast(rawptr)ruby_sprite_get_offset, 0)
	mrb.define_method(g.mrb_state, c, "offset=", cast(rawptr)ruby_sprite_set_offset, 1)
	mrb.define_method(g.mrb_state, c, "scale", cast(rawptr)ruby_sprite_get_scale, 0)
	mrb.define_method(g.mrb_state, c, "scale=", cast(rawptr)ruby_sprite_set_scale, 1)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_sprite_draw, 1)
}
