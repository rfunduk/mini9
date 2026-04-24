package engine

import mrb "lib:mruby"
import rl "lib:raylib"

// Shared drawing utility: apply a Rect as a scissor region, offset by the
// caller's draw position. Returns true when scissor was activated — caller
// must pair with `rl.EndScissorMode()`.
_clip :: proc(clip: Maybe(rl.Rectangle), offset: rl.Vector2) -> bool {
	cr, ok := clip.?
	if !ok { return false }
	rl.BeginScissorMode(i32(offset.x + cr.x), i32(offset.y + cr.y), i32(cr.width), i32(cr.height))
	return true
}

// kwarg extraction helpers — let ruby wrappers stay one line per kwarg.

_parse_offset_kwarg :: proc(state: mrb.State, kwargs: mrb.Value) -> rl.Vector2 {
	val := mrb.kwarg(state, kwargs, sym.offset)
	if val == mrb.NIL { return {} }
	off := extract_native(rl.Vector2, val)
	if off == nil { return {} }
	return off^
}

_parse_color_kwarg :: proc(
	state: mrb.State,
	kwargs: mrb.Value,
	default_color: rl.Color = {255, 255, 255, 255},
) -> rl.Color {
	val := mrb.kwarg(state, kwargs, sym.color)
	if val == mrb.NIL { return default_color }
	c := extract_native(rl.Color, val)
	if c == nil { return default_color }
	return c^
}

_parse_clip_kwarg :: proc(state: mrb.State, kwargs: mrb.Value) -> Maybe(rl.Rectangle) {
	val := mrb.kwarg(state, kwargs, sym.clip)
	if val == mrb.NIL { return nil }
	cr := extract_native(rl.Rectangle, val)
	if cr == nil { return nil }
	return cr^
}

_parse_bool_kwarg :: proc(
	state: mrb.State,
	kwargs: mrb.Value,
	sym_val: mrb.Value,
	default_value: bool = false,
) -> bool {
	val := mrb.kwarg(state, kwargs, sym_val)
	if val == mrb.NIL { return default_value }
	return mrb.boolean(val)
}

_parse_f32_kwarg :: proc(
	state: mrb.State,
	kwargs: mrb.Value,
	sym_val: mrb.Value,
	default_value: f32,
) -> f32 {
	val := mrb.kwarg(state, kwargs, sym_val)
	if val == mrb.NIL { return default_value }
	return f32(mrb.to_f64(val))
}
