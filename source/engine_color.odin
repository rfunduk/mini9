package engine

import "core:math"
import "core:strconv"
import "core:strings"
import mrb "lib:mruby"
import rl "lib:raylib"

ruby_color_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_color :: proc(c: rl.Color) -> mrb.Value {
	color_ptr := mrb.alloc(g.mrb_state, c)

	color_class := mrb.class_get(g.mrb_state, "Color")
	ruby_obj := mrb.obj_new(g.mrb_state, color_class, 0, nil)

	mrb.data_init(ruby_obj, color_ptr, NATIVE_TO_MRUBY_TYPE[rl.Color])

	return ruby_obj
}

// RUBY FUNCTION: color(r, g, b, a=255) -> returns Color object (integer values 0-255)
// @engine_method: name="_color_int", aspec=ARGS_ARG(3,1)
ruby_color_int :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r, g, b, a: f64
	argc := mrb.get_args(state, "fff|f", &r, &g, &b, &a)

	if argc == 3 { a = 255 }

	color := rl.Color{u8(clamp(r, 0, 255)), u8(clamp(g, 0, 255)), u8(clamp(b, 0, 255)), u8(clamp(a, 0, 255))}

	return create_color(color)
}

// RUBY FUNCTION: color_normalized(r, g, b, a=1.0) -> returns Color object (normalized values 0-1)
// @engine_method: name="_color_normalized", aspec=ARGS_ARG(3,1)
ruby_color_normalized :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r, g, b, a: f64
	argc := mrb.get_args(state, "fff|f", &r, &g, &b, &a)

	if argc == 3 { a = 1.0 }

	// convert normalized values to 0-255 range
	color := rl.Color {
		u8(clamp(r * 255.0, 0, 255)),
		u8(clamp(g * 255.0, 0, 255)),
		u8(clamp(b * 255.0, 0, 255)),
		u8(clamp(a * 255.0, 0, 255)),
	}

	return create_color(color)
}

// RUBY FUNCTION: color_hex(hex_string) -> returns Color object from hex string
// @engine_method: name="_color_hex", aspec=ARGS_REQ(1)
ruby_color_hex :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	hex_val: mrb.Value
	mrb.get_args(state, "o", &hex_val)

	str_obj := mrb.obj_as_string(state, hex_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	hex_str := string(c_str)

	// remove # prefix if present
	if strings.has_prefix(hex_str, "#") { hex_str = hex_str[1:] }

	// parse hex string using strconv, fallback to black
	hex_value, ok := strconv.parse_int(hex_str, 16)
	if !ok { return create_color({0, 0, 0, 255}) }

	// convert hex to Color based on string length
	color: rl.Color
	switch len(hex_str) {
	case 3:
		// RGB (e.g., "F0A" -> "FF00AA")
		r := u8((hex_value >> 8) & 0xF)
		g := u8((hex_value >> 4) & 0xF)
		b := u8(hex_value & 0xF)
		color = {r * 17, g * 17, b * 17, 255} // 17 = 255/15 to expand 4-bit to 8-bit

	case 6:
		// RRGGBB (e.g., "FF0000")
		color = {u8((hex_value >> 16) & 0xFF), u8((hex_value >> 8) & 0xFF), u8(hex_value & 0xFF), 255}

	case 8:
		// RRGGBBAA (e.g., "FF000080")
		color = {
			u8((hex_value >> 24) & 0xFF),
			u8((hex_value >> 16) & 0xFF),
			u8((hex_value >> 8) & 0xFF),
			u8(hex_value & 0xFF),
		}

	case:
		// invalid format, return black
		color = {0, 0, 0, 255}
	}

	return create_color(color)
}

ruby_color_equal :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	other_val: mrb.Value
	mrb.get_args(state, "o", &other_val)

	color := extract_native(rl.Color, self)
	other := extract_or_nil(rl.Color, other_val)
	if other == nil { return mrb.FALSE }

	return color^ == other^ ? mrb.TRUE : mrb.FALSE
}

ruby_color_get_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	return mrb.boxing_int_value(state, color == nil ? 0 : i32(color.r))
}

ruby_color_get_g :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	return mrb.boxing_int_value(state, color == nil ? 0 : i32(color.g))
}

ruby_color_get_b :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	return mrb.boxing_int_value(state, color == nil ? 0 : i32(color.b))
}

ruby_color_get_a :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	return mrb.boxing_int_value(state, color == nil ? 0 : i32(color.a))
}

ruby_color_set_r :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	val: mrb.Value
	mrb.get_args(state, "o", &val)
	color := extract_native(rl.Color, self)
	if color != nil { color.r = u8(clamp(mrb.to_f64(val), 0, 255)) }
	return val
}

ruby_color_set_g :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	val: mrb.Value
	mrb.get_args(state, "o", &val)
	color := extract_native(rl.Color, self)
	if color != nil { color.g = u8(clamp(mrb.to_f64(val), 0, 255)) }
	return val
}

ruby_color_set_b :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	val: mrb.Value
	mrb.get_args(state, "o", &val)
	color := extract_native(rl.Color, self)
	if color != nil { color.b = u8(clamp(mrb.to_f64(val), 0, 255)) }
	return val
}

ruby_color_set_a :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	val: mrb.Value
	mrb.get_args(state, "o", &val)
	color := extract_native(rl.Color, self)
	if color != nil { color.a = u8(clamp(mrb.to_f64(val), 0, 255)) }
	return val
}

// Adjust HSV saturation by `delta`, preserving the original alpha (ColorFromHSV
// always returns alpha 255). delta > 0 saturates, < 0 desaturates.
color_adjust_saturation :: proc(c: rl.Color, delta: f32) -> rl.Color {
	hsv := rl.ColorToHSV(c)
	out := rl.ColorFromHSV(hsv.x, clamp(hsv.y + delta, 0, 1), hsv.z)
	out.a = c.a
	return out
}

// RUBY METHOD: lighten(amount=0.1) -> new Color brightened toward white
ruby_color_lighten :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	amount: f64 = 0.1
	mrb.get_args(state, "|f", &amount)
	color := extract_native(rl.Color, self)
	return create_color(rl.ColorBrightness(color^, f32(amount)))
}

// RUBY METHOD: darken(amount=0.1) -> new Color darkened toward black
ruby_color_darken :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	amount: f64 = 0.1
	mrb.get_args(state, "|f", &amount)
	color := extract_native(rl.Color, self)
	return create_color(rl.ColorBrightness(color^, -f32(amount)))
}

// RUBY METHOD: saturate(amount=0.1) -> new Color with more HSV saturation
ruby_color_saturate :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	amount: f64 = 0.1
	mrb.get_args(state, "|f", &amount)
	color := extract_native(rl.Color, self)
	return create_color(color_adjust_saturation(color^, f32(amount)))
}

// RUBY METHOD: desaturate(amount=0.1) -> new Color with less HSV saturation
ruby_color_desaturate :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	amount: f64 = 0.1
	mrb.get_args(state, "|f", &amount)
	color := extract_native(rl.Color, self)
	return create_color(color_adjust_saturation(color^, -f32(amount)))
}

// RUBY METHOD: grayscale -> new Color fully desaturated (HSV saturation 0)
ruby_color_grayscale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	hsv := rl.ColorToHSV(color^)
	out := rl.ColorFromHSV(hsv.x, 0, hsv.z)
	out.a = color.a
	return create_color(out)
}

// RUBY METHOD: contrast(amount) -> new Color with contrast correction (-1.0..1.0)
ruby_color_contrast :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	amount: f64
	mrb.get_args(state, "f", &amount)
	color := extract_native(rl.Color, self)
	return create_color(rl.ColorContrast(color^, f32(amount)))
}

// RUBY METHOD: rotate_hue(degrees) -> new Color with hue rotated around the wheel
ruby_color_rotate_hue :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	degrees: f64
	mrb.get_args(state, "f", &degrees)
	color := extract_native(rl.Color, self)
	hsv := rl.ColorToHSV(color^)
	hue := math.mod(hsv.x + f32(degrees), 360)
	if hue < 0 { hue += 360 }
	out := rl.ColorFromHSV(hue, hsv.y, hsv.z)
	out.a = color.a
	return create_color(out)
}

// RUBY METHOD: fade(alpha) -> new Color with alpha applied (0.0..1.0)
ruby_color_fade :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	alpha: f64
	mrb.get_args(state, "f", &alpha)
	color := extract_native(rl.Color, self)
	return create_color(rl.ColorAlpha(color^, f32(alpha)))
}

// RUBY METHOD: invert -> new Color with RGB channels inverted (alpha preserved)
ruby_color_invert :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	color := extract_native(rl.Color, self)
	return create_color({255 - color.r, 255 - color.g, 255 - color.b, color.a})
}

// RUBY METHOD: mix(other, t=0.5) -> new Color linearly interpolated toward other
ruby_color_mix :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other_val: mrb.Value
	t: f64 = 0.5
	mrb.get_args(state, "o|f", &other_val, &t)
	color := extract_native(rl.Color, self)
	other := extract_or_raise(rl.Color, other_val, "Color#mix expects a Color")
	return create_color(rl.ColorLerp(color^, other^, clamp(f32(t), 0, 1)))
}

// RUBY METHOD: tint(other) -> new Color multiplied channel-wise with other
ruby_color_tint :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other_val: mrb.Value
	mrb.get_args(state, "o", &other_val)
	color := extract_native(rl.Color, self)
	other := extract_or_raise(rl.Color, other_val, "Color#tint expects a Color")
	return create_color(rl.ColorTint(color^, other^))
}

setup_color :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Color")

	mrb.define_method(g.mrb_state, c, "r", cast(rawptr)ruby_color_get_r, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "g", cast(rawptr)ruby_color_get_g, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "b", cast(rawptr)ruby_color_get_b, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "a", cast(rawptr)ruby_color_get_a, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "r=", cast(rawptr)ruby_color_set_r, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "g=", cast(rawptr)ruby_color_set_g, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "b=", cast(rawptr)ruby_color_set_b, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "a=", cast(rawptr)ruby_color_set_a, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "==", cast(rawptr)ruby_color_equal, mrb.ARGS_REQ(1))

	mrb.define_method(g.mrb_state, c, "lighten", cast(rawptr)ruby_color_lighten, mrb.ARGS_OPT(1))
	mrb.define_method(g.mrb_state, c, "darken", cast(rawptr)ruby_color_darken, mrb.ARGS_OPT(1))
	mrb.define_method(g.mrb_state, c, "saturate", cast(rawptr)ruby_color_saturate, mrb.ARGS_OPT(1))
	mrb.define_method(g.mrb_state, c, "desaturate", cast(rawptr)ruby_color_desaturate, mrb.ARGS_OPT(1))
	mrb.define_method(g.mrb_state, c, "grayscale", cast(rawptr)ruby_color_grayscale, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "contrast", cast(rawptr)ruby_color_contrast, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "rotate_hue", cast(rawptr)ruby_color_rotate_hue, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "fade", cast(rawptr)ruby_color_fade, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "invert", cast(rawptr)ruby_color_invert, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "mix", cast(rawptr)ruby_color_mix, mrb.ARGS_ARG(1, 1))
	mrb.define_method(g.mrb_state, c, "tint", cast(rawptr)ruby_color_tint, mrb.ARGS_REQ(1))
}
