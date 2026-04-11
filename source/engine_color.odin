package engine

import "core:strconv"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

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
// @engine_method: name="_color_int", arity=-1
ruby_color_int :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	r, g, b, a: f64
	argc := mrb.get_args(state, "fff|f", &r, &g, &b, &a)

	if argc == 3 { a = 255 }

	color := rl.Color{u8(clamp(r, 0, 255)), u8(clamp(g, 0, 255)), u8(clamp(b, 0, 255)), u8(clamp(a, 0, 255))}

	return create_color(color)
}

// RUBY FUNCTION: color_normalized(r, g, b, a=1.0) -> returns Color object (normalized values 0-1)
// @engine_method: name="_color_normalized", arity=-1
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
// @engine_method: name="_color_hex", arity=1
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
	other := extract_native(rl.Color, other_val)

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
	value: f64
	mrb.get_args(state, "f", &value)
	color := extract_native(rl.Color, self)
	if color != nil { color.r = u8(clamp(value, 0, 255)) }
	return self
}

ruby_color_set_g :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	value: f64
	mrb.get_args(state, "f", &value)
	color := extract_native(rl.Color, self)
	if color != nil { color.g = u8(clamp(value, 0, 255)) }
	return self
}

ruby_color_set_b :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	value: f64
	mrb.get_args(state, "f", &value)
	color := extract_native(rl.Color, self)
	if color != nil { color.b = u8(clamp(value, 0, 255)) }
	return self
}

ruby_color_set_a :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	value: f64
	mrb.get_args(state, "f", &value)
	color := extract_native(rl.Color, self)
	if color != nil { color.a = u8(clamp(value, 0, 255)) }
	return self
}

setup_color :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Color")

	mrb.define_method(g.mrb_state, c, "r", cast(rawptr)ruby_color_get_r, 0)
	mrb.define_method(g.mrb_state, c, "g", cast(rawptr)ruby_color_get_g, 0)
	mrb.define_method(g.mrb_state, c, "b", cast(rawptr)ruby_color_get_b, 0)
	mrb.define_method(g.mrb_state, c, "a", cast(rawptr)ruby_color_get_a, 0)
	mrb.define_method(g.mrb_state, c, "r=", cast(rawptr)ruby_color_set_r, 1)
	mrb.define_method(g.mrb_state, c, "g=", cast(rawptr)ruby_color_set_g, 1)
	mrb.define_method(g.mrb_state, c, "b=", cast(rawptr)ruby_color_set_b, 1)
	mrb.define_method(g.mrb_state, c, "a=", cast(rawptr)ruby_color_set_a, 1)
	mrb.define_method(g.mrb_state, c, "==", cast(rawptr)ruby_color_equal, 1)
}
