package engine

import "core:math"
import lin "core:math/linalg"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

// 8-directional offsets for text outline
OUTLINE_OFFSETS :: [?]rl.Vector2{{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}}

Text_Align :: enum {
	LEFT,
	CENTER,
	RIGHT,
}

// RUBY FUNCTION: text(pos, text, font: nil, align: Text::LEFT, rotation: 0, scale: 1, spacing: 1, color: WHITE, outline: false)
// @engine_method: name="text", arity=-1
ruby_text :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	text_val, pos_val, font_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "ooo|H", &text_val, &pos_val, &font_val, &kwargs)

	// extract position Vector2
	pos_vec := extract_native(rl.Vector2, pos_val)
	if pos_vec == nil { return mrb.NIL }

	// extract text string
	str_obj := mrb.obj_as_string(state, text_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	text := strings.clone_from_cstring(c_str, context.temp_allocator)

	// extract font
	font := extract_native(rl.Font, font_val)

	// default values
	align: Text_Align = .LEFT
	spacing: f32 = 1.0
	color: rl.Color = {255, 255, 255, 255}
	outline: rl.Color = {0, 0, 0, 0}
	scale: f32 = 1.0
	rotation: f32 = 0.0
	offset: rl.Vector2 = {0, 0}

	if argc == 4 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)

		if "font" in hash {
			if hash["font"] != mrb.NIL {
				font = extract_native(rl.Font, hash["font"])
			}
		}
		if "offset" in hash {
			offset = extract_native(rl.Vector2, hash["offset"])^
		}
		if "align" in hash {
			align_int := mrb.integer(hash["align"])
			align = Text_Align(align_int)
		}
		if "rotation" in hash {
			rotation = f32(to_f64(hash["rotation"]))
		}
		if "spacing" in hash {
			spacing = f32(to_f64(hash["spacing"]))
		}
		if "scale" in hash {
			scale = f32(to_f64(hash["scale"]))
		}
		if "color" in hash {
			color = extract_native(rl.Color, hash["color"])^
		}
		if "outline" in hash {
			wants_black := hash["outline"] == mrb.TRUE
			outline = wants_black ? {0, 0, 0, 255} : extract_native(rl.Color, hash["outline"])^
		}
	}

	text_cstr := strings.clone_to_cstring(text, context.temp_allocator)

	draw_pos := pos_vec^

	switch align {
	case .LEFT:
		{  } 	// nothing to do
	case .CENTER:
		text_size := rl.MeasureTextEx(font^, text_cstr, f32(font^.baseSize) * f32(scale), spacing * scale)
		offset.x += text_size.x / 2
	case .RIGHT:
		text_size := rl.MeasureTextEx(font^, text_cstr, f32(font^.baseSize) * f32(scale), spacing * scale)
		offset.x += text_size.x
	}

	draw_pos = lin.floor(draw_pos)
	offset = lin.floor(offset)
	size := math.floor(f32(font^.baseSize) * scale)

	if outline.a != 0 {
		for o in OUTLINE_OFFSETS {
			rl.DrawTextPro(font^, text_cstr, draw_pos, offset + o, rotation, size, spacing * scale, outline)
		}
	}

	// rl.DrawCircleV(draw_pos + offset, 5, rl.RAYWHITE)
	rl.DrawTextPro(font^, text_cstr, draw_pos, offset, rotation, size, spacing * scale, color)

	return mrb.NIL
}

setup_text :: proc() {
	// also expose text alignment constants
	tc := mrb.class_get(g.mrb_state, "Text")
	mrb.define_const(g.mrb_state, tc, "LEFT", mrb.boxing_int_value(g.mrb_state, i32(Text_Align.LEFT)))
	mrb.define_const(g.mrb_state, tc, "CENTER", mrb.boxing_int_value(g.mrb_state, i32(Text_Align.CENTER)))
	mrb.define_const(g.mrb_state, tc, "RIGHT", mrb.boxing_int_value(g.mrb_state, i32(Text_Align.RIGHT)))
}
