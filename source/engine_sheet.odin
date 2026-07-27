package engine

import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "lib:raylib"

Sheet :: struct {
	atlas:  ^Texture,
	size:   V2,
	frames: uint,
}

ruby_sheet_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

// RUBY FUNCTION: sheet(texture, size: nil, frames: 1) -> returns Sheet object
// @engine_method: name="sheet", aspec=ARGS_ARG(1,1)
ruby_sheet :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	atlas_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &atlas_val, &kwargs)

	atlas := extract_or_nil(Texture, atlas_val)
	found_atlas: bool = atlas != nil && atlas.status != .UNLOADED

	size := V2{-1, -1}
	frames: uint = 0 // 0 means auto-calculate when needed

	if argc == 2 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.size)
		if val != mrb.NIL { size = extract_or_raise(V2, val, "sheet: size must be a Vector2")^ }
		val = mrb.kwarg(state, kwargs, sym.frames)
		if val != mrb.NIL { frames = uint(mrb.to_int(val)) }
		val = mrb.kwarg(state, kwargs, sym.atlas)
		if a := extract_or_nil(Texture, val); a != nil {
			atlas = a
			found_atlas = true
		}
	}

	if !found_atlas {
		return mrb.raise_error(state, "ArgumentError", "Sheet requires a texture to use as atlas")
	}

	sheet_obj := create_sheet(Sheet{atlas = atlas, size = size, frames = frames})

	// only set @atlas since it's referenced in Ruby code (e.g. to_s method)
	atlas_sym := mrb.intern_cstr(state, "@atlas")
	mrb.iv_set(state, sheet_obj, atlas_sym, atlas_val)

	return sheet_obj
}

create_sheet :: proc(s: Sheet) -> mrb.Value {
	context = global_context

	sheet_ptr := mrb.alloc(g.mrb_state, s)

	sheet_class := mrb.class_get(g.mrb_state, "Sheet")
	ruby_obj := mrb.obj_new(g.mrb_state, sheet_class, 0, nil)

	mrb.data_init(ruby_obj, sheet_ptr, NATIVE_TO_MRUBY_TYPE[Sheet])

	return ruby_obj
}

// get sheet frame count, auto-calculating if needed
get_sheet_frames :: proc(sheet: ^Sheet) -> uint {
	if sheet.frames == 0 && sheet.size.x > 0 && sheet.size.y > 0 && sheet.atlas.status == .LOADED {
		cols := int(sheet.atlas.w / sheet.size.x)
		rows := int(sheet.atlas.h / sheet.size.y)
		if cols > 0 && rows > 0 {
			sheet.frames = uint(cols * rows)
		} else {
			sheet.frames = 1
		}
	}
	return sheet.frames == 0 ? 1 : sheet.frames
}

// RUBY METHOD: sheet.size -> gets sheet frame size
ruby_sheet_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sheet := extract_native(Sheet, self)
	if sheet == nil { return mrb.NIL }
	return create_vector2(sheet.size)
}

// RUBY METHOD: sheet.frames -> gets sheet frame count
ruby_sheet_get_frames :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	sheet := extract_native(Sheet, self)
	if sheet == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, i32(get_sheet_frames(sheet)))
}

ruby_sheet_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	sheet := extract_native(Sheet, self)
	if sheet == nil || sheet.atlas == nil || sheet.atlas.status != .LOADED {
		return mrb.NIL
	}

	did_clip := false
	frame: uint = 0
	fliph := false
	flipv := false
	rotation: f32 = 0
	offset := V2{0, 0}
	scale := V2{1, 1}
	origin := V2{0, 0}

	if argc == 1 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.frame)
		if val != mrb.NIL {
			frame = uint(mrb.to_int(val))
			frame = frame % get_sheet_frames(sheet) // wrap around if needed
		}
		val = mrb.kwarg(state, kwargs, sym.fliph)
		if val != mrb.NIL { fliph = mrb.boolean(val) }
		val = mrb.kwarg(state, kwargs, sym.flipv)
		if val != mrb.NIL { flipv = mrb.boolean(val) }
		val = mrb.kwarg(state, kwargs, sym.rotation)
		if val != mrb.NIL { rotation = f32(mrb.to_f64(val)) * 180.0 / math.PI }
		val = mrb.kwarg(state, kwargs, sym.offset)
		if val != mrb.NIL {
			offset = extract_or_raise(V2, val, "sheet: offset must be a Vector2")^
			offset = lin.floor(offset)
		}
		val = mrb.kwarg(state, kwargs, sym.origin)
		if val != mrb.NIL {
			origin = extract_or_raise(V2, val, "sheet: origin must be a Vector2")^
			origin = lin.floor(origin)
		}
		val = mrb.kwarg(state, kwargs, sym.scale)
		if val != mrb.NIL { scale = extract_or_raise(V2, val, "sheet: scale must be a Vector2")^ }
	}

	did_clip = _clip(_parse_clip_kwarg(state, kwargs), offset)

	// calculate source rectangle in logical sheet coords
	frame_width := sheet.size.x > 0 ? sheet.size.x : sheet.atlas.w
	frame_height := sheet.size.y > 0 ? sheet.size.y : sheet.atlas.h

	cols := int(sheet.atlas.w / frame_width)
	if cols == 0 { cols = 1 }

	col := int(frame) % cols
	row := int(frame) / cols

	frame_x := f32(col) * frame_width
	frame_y := f32(row) * frame_height

	offset = lin.floor(offset + origin)

	// translate into atlas pixel space (no-op for STANDALONE since origin = 0)
	source := rl.Rectangle {
		x      = math.floor(sheet.atlas.tex_origin.x + frame_x),
		y      = math.floor(sheet.atlas.tex_origin.y + frame_y),
		width  = math.floor(fliph ? -frame_width : frame_width),
		height = math.floor(flipv ? -frame_height : frame_height),
	}

	dest := rl.Rectangle {
		x      = offset.x,
		y      = offset.y,
		width  = math.floor(abs(frame_width) * scale.x),
		height = math.floor(abs(frame_height) * scale.y),
	}

	rl.DrawTexturePro(sheet.atlas.tex, source, dest, origin, rotation, rl.WHITE)

	if did_clip { rl.EndScissorMode() }

	return self
}

setup_sheet :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Sheet")
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_sheet_get_size, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "frames", cast(rawptr)ruby_sheet_get_frames, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_sheet_draw, mrb.ARGS_OPT(1))
}
