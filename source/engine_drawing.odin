package engine

import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

// RUBY FUNCTION: pixel(pos, color: WHITE) -> draws a single pixel
// @engine_method: name="pixel", arity=-1
ruby_pixel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	pos_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &pos_val, &kwargs)

	pos_vec := extract_native(rl.Vector2, pos_val)
	draw_color := rl.Color{255, 255, 255, 255}

	if argc == 2 && kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)
		if "color" in hash { draw_color = extract_native(rl.Color, hash["color"])^ }
	}

	rl.DrawPixelV(lin.floor(pos_vec^), draw_color)

	return mrb.NIL
}

// RUBY FUNCTION: circle(pos, radius, color: WHITE) -> draws a circle
// @engine_method: name="circle", arity=-1
ruby_circle :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val, r_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "oo|H", &pos_val, &r_val, &kwargs)

	pos_vec := extract_native(rl.Vector2, pos_val)
	pos := lin.floor(pos_vec^)
	radius := f32(mrb.to_f64(r_val))

	draw_color := rl.Color{255, 255, 255, 255} // Default to white
	filled: bool = false
	did_clip: bool = false

	if argc == 3 && kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)
		if "color" in hash { draw_color = extract_native(rl.Color, hash["color"])^ }
		if "filled" in hash { filled = mrb.boolean(hash["filled"]) }
		if "clip" in hash { did_clip = _clip(hash["clip"], pos) }
	}

	if filled {
		rl.DrawCircleV(pos, radius, draw_color)
	} else {
		rl.DrawCircleLinesV(pos, radius, draw_color)
	}

	if did_clip { rl.EndScissorMode() }

	return mrb.NIL
}

// RUBY FUNCTION: oval(pos, size, color: WHITE, filled: false) -> draws an ellipse
// @engine_method: name="oval", arity=-1
ruby_oval :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val, size_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "oo|H", &pos_val, &size_val, &kwargs)

	pos_vec := extract_native(rl.Vector2, pos_val)
	size_vec := extract_native(rl.Vector2, size_val)

	pos := lin.floor(pos_vec^)
	size := lin.floor(size_vec^)

	draw_color := rl.Color{255, 255, 255, 255} // Default to white
	filled: bool = false
	did_clip: bool = false

	if argc == 3 && kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)
		if "color" in hash { draw_color = extract_native(rl.Color, hash["color"])^ }
		if "filled" in hash { filled = mrb.boolean(hash["filled"]) }
		if "clip" in hash { did_clip = _clip(hash["clip"], pos) }
	}

	if filled {
		rl.DrawEllipse(i32(pos.x), i32(pos.y), size.x, size.y, draw_color)
	} else {
		rl.DrawEllipseLines(i32(pos.x), i32(pos.y), size.x, size.y, draw_color)
	}

	if did_clip { rl.EndScissorMode() }

	return mrb.NIL
}

// RUBY FUNCTION: line(from, to = nil, color: WHITE) -> draws a line
// @engine_method: name="line", arity=-1
ruby_line :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	from_val, to_val, kwargs: mrb.Value
	mrb.get_args(state, "oo|H", &from_val, &to_val, &kwargs)

	from_vec: ^rl.Vector2
	to_vec: ^rl.Vector2

	from_vec = extract_native(rl.Vector2, from_val)
	to_vec = extract_native(rl.Vector2, to_val)
	if from_vec == nil || to_vec == nil { return mrb.NIL }

	from := lin.floor(from_vec^)
	to := lin.floor(to_vec^)

	draw_color := rl.Color{255, 255, 255, 255}
	thickness: f64 = 1.0
	did_clip: bool = false

	if kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)
		if "color" in hash { draw_color = extract_native(rl.Color, hash["color"])^ }
		if "thickness" in hash { thickness = mrb.to_f64(hash["thickness"]) }
		if "clip" in hash { did_clip = _clip(hash["clip"], from) }
	}

	rl.DrawLineEx(from, to, f32(thickness), draw_color)

	if did_clip { rl.EndScissorMode() }

	return mrb.NIL
}

// RUBY FUNCTION: rectangle(rect_or_pos, size=nil, color: WHITE, thickness: 1, filled: false, rounded: 0)
// Accepts either rectangle(rect) or rectangle(pos, size). Draws a rectangle.
// @engine_method: name="rectangle", arity=-1
ruby_rectangle :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	a_val, b_val, kwargs: mrb.Value
	mrb.get_args(state, "o|oH", &a_val, &b_val, &kwargs)

	// With format "o|oH", a trailing kwargs hash from a 1-positional call
	// like `rectangle(box, color: P.red)` lands in the optional `o` slot
	// (b_val) before `H` ever sees it. Re-route it to kwargs so style is
	// applied in the rectangle(rect) form.
	if kwargs == mrb.NIL && b_val != mrb.NIL && mrb.hash_p(b_val) {
		kwargs = b_val
		b_val = mrb.NIL
	}

	pos: rl.Vector2
	size: rl.Vector2

	if is_native(rl.Rectangle, a_val) {
		// rectangle(rect) form
		r := extract_native(rl.Rectangle, a_val)
		pos = {r.x, r.y}
		size = {r.width, r.height}
	} else {
		// rectangle(pos, size) form
		pos_vec := extract_native(rl.Vector2, a_val)
		size_vec := extract_native(rl.Vector2, b_val)
		if pos_vec == nil || size_vec == nil { return mrb.NIL }
		pos = pos_vec^
		size = size_vec^
	}

	pos = lin.floor(pos)
	size = lin.floor(size)

	draw_color := rl.Color{255, 255, 255, 255} // Default to white
	thickness: f32 = 1.0
	rounded: f32 = 0.0
	filled: bool = false
	did_clip: bool = false

	if kwargs != mrb.NIL {
		hash := mrb.parse_kwargs(state, kwargs)

		if "color" in hash { draw_color = extract_native(rl.Color, hash["color"])^ }
		if "rounded" in hash { rounded = f32(mrb.to_f64(hash["rounded"])) / 100.0 }
		if "thickness" in hash { thickness = f32(mrb.to_f64(hash["thickness"])) }
		if "filled" in hash { filled = mrb.boolean(hash["filled"]) }
		if "clip" in hash { did_clip = _clip(hash["clip"], pos) }
	}

	if filled {
		if rounded > 0 {
			rl.DrawRectangleRounded({pos.x, pos.y, size.x, size.y}, rounded, 10, draw_color)
		} else {
			rl.DrawRectangleV(pos, size, draw_color)
		}
	} else {
		if rounded > 0 {
			rl.DrawRectangleRoundedLinesEx(
				{pos.x, pos.y, size.x, size.y},
				rounded,
				i32(max(size.x, size.y) / 2),
				thickness,
				draw_color,
			)
		} else {
			rl.DrawRectangleLinesEx({pos.x, pos.y, size.x, size.y}, thickness, draw_color)
		}
	}

	if did_clip { rl.EndScissorMode() }

	return mrb.NIL
}

_clip :: proc(clip_val: mrb.Value, offset: rl.Vector2) -> bool {
	if clip_val == mrb.NIL { return false }

	clip_rect := extract_native(rl.Rectangle, clip_val)
	if clip_rect == nil { return false }

	adjusted_clip := rl.Rectangle {
		x      = offset.x + clip_rect.x,
		y      = offset.y + clip_rect.y,
		width  = clip_rect.width,
		height = clip_rect.height,
	}

	rl.BeginScissorMode(
		i32(adjusted_clip.x),
		i32(adjusted_clip.y),
		i32(adjusted_clip.width),
		i32(adjusted_clip.height),
	)
	return true
}
