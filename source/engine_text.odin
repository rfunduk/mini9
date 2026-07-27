package engine

import "core:math"
import lin "core:math/linalg"
import "core:strings"
import mrb "lib:mruby"
import rl "lib:raylib"

// 8-directional offsets for text outline
OUTLINE_OFFSETS :: [?]V2{{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}}

Text :: struct {
	str:      cstring,
	font_val: mrb.Value, // GC-registered Font object; not nil once constructed
}

ruby_text_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr == nil { return }
	t := cast(^Text)ptr
	if t.str != nil { delete(t.str) }
	if t.font_val != mrb.NIL { mrb.gc_unregister(state, t.font_val) }
	mrb.free(state, ptr)
}

create_text :: proc(str: string, font_val: mrb.Value) -> mrb.Value {
	t := Text{}
	t.str = strings.clone_to_cstring(str)
	t.font_val = font_val
	mrb.gc_register(g.mrb_state, font_val)

	ptr := mrb.alloc(g.mrb_state, t)
	class := mrb.class_get(g.mrb_state, "Text")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Text])
	return ruby_obj
}

// RUBY FUNCTION: text(str, font) — returns a Text shape.
// @engine_method: name="text", aspec=ARGS_REQ(2)
ruby_text :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	text_val, font_val: mrb.Value
	mrb.get_args(state, "oo", &text_val, &font_val)

	font := extract_native(rl.Font, font_val)
	if font == nil {
		return mrb.raise_error(state, "ArgumentError", "text(str, font): font must be a Font")
	}

	str_obj := mrb.obj_as_string(state, text_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	s := strings.clone_from_cstring(c_str, context.temp_allocator)

	return create_text(s, font_val)
}

ruby_text_get_str :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Text, self)
	if t == nil || t.str == nil { return mrb.str_new_cstr(state, "") }
	return mrb.str_new_cstr(state, t.str)
}

ruby_text_get_font :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t := extract_native(Text, self)
	if t == nil { return mrb.NIL }
	return t.font_val
}

ruby_text_measure :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	t := extract_native(Text, self)
	if t == nil { return create_vector2({}) }

	font := extract_native(rl.Font, t.font_val)
	if font == nil { return create_vector2({}) }

	// cannot measure during INIT, fonts not loaded yet
	if g.phase == .INIT && font.baseSize == 0 {
		return mrb.raise_error(
			state,
			"RuntimeError",
			"Text#measure called during setup, before fonts are loaded - measure from update/draw",
		)
	}

	scale: f32 = 1.0
	spacing: f32 = 1.0

	val := mrb.kwarg(state, kwargs, sym.scale)
	if val != mrb.NIL { scale = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.spacing)
	if val != mrb.NIL { spacing = f32(mrb.to_f64(val)) }

	size := rl.MeasureTextEx(font^, t.str, f32(font.baseSize) * scale, spacing * scale)
	return create_vector2(size)
}

ruby_text_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	t := extract_native(Text, self)
	if t == nil { return mrb.NIL }

	font := extract_native(rl.Font, t.font_val)
	if font == nil { return mrb.NIL }

	spacing: f32 = 1.0
	color: rl.Color = {255, 255, 255, 255}
	outline: rl.Color = {0, 0, 0, 0}
	scale: f32 = 1.0
	rotation: f32 = 0.0
	offset := V2{0, 0}
	origin := V2{0, 0}

	val: mrb.Value
	val = mrb.kwarg(state, kwargs, sym.offset)
	if val != mrb.NIL { offset = extract_or_raise(V2, val, "text: offset must be a Vector2")^ }
	val = mrb.kwarg(state, kwargs, sym.origin)
	if val != mrb.NIL {
		origin = extract_or_raise(V2, val, "text: origin must be a Vector2")^
		origin = lin.floor(origin)
	}
	val = mrb.kwarg(state, kwargs, sym.rotation)
	if val != mrb.NIL { rotation = f32(mrb.to_f64(val)) * 180 / math.PI }
	val = mrb.kwarg(state, kwargs, sym.spacing)
	if val != mrb.NIL { spacing = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.scale)
	if val != mrb.NIL { scale = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.color)
	if val != mrb.NIL { color = extract_or_raise(rl.Color, val, "text: color must be a Color")^ }
	val = mrb.kwarg(state, kwargs, sym.outline)
	if val != mrb.NIL {
		if val == mrb.TRUE {
			outline = rl.BLACK
		} else {
			outline = extract_or_raise(rl.Color, val, "text: outline must be Color|true")^
		}
	}

	size := math.floor(f32(font^.baseSize) * scale)
	offset = lin.floor(offset + origin)

	if outline.a != 0 {
		for o in OUTLINE_OFFSETS {
			rl.DrawTextPro(
				font^,
				t.str,
				offset,
				origin + o * scale,
				rotation,
				size,
				spacing * scale,
				outline,
			)
		}
	}

	rl.DrawTextPro(font^, t.str, offset, origin, rotation, size, spacing * scale, color)

	return mrb.NIL
}

setup_text :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Text")
	mrb.define_method(g.mrb_state, c, "str", cast(rawptr)ruby_text_get_str, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "font", cast(rawptr)ruby_text_get_font, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "measure", cast(rawptr)ruby_text_measure, mrb.ARGS_OPT(1))
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_text_draw, mrb.ARGS_OPT(1))
}
