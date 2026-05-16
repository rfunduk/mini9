package engine

import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "lib:raylib"

Poly :: struct {
	verts: [dynamic]rl.Vector2,
}

ruby_poly_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr == nil { return }
	p := cast(^Poly)ptr
	delete(p.verts)
	mrb.free(state, ptr)
}

create_poly :: proc(verts: []rl.Vector2) -> mrb.Value {
	p := Poly{}
	reserve(&p.verts, len(verts))
	for v in verts { append(&p.verts, v) }

	ptr := mrb.alloc(g.mrb_state, p)
	class := mrb.class_get(g.mrb_state, "Poly")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Poly])
	return ruby_obj
}

// RUBY FUNCTION: poly(verts) — verts is an Array of Vector2 (min 3).
// @engine_method: name="poly", aspec=ARGS_REQ(1)
ruby_poly :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	arr: mrb.Value
	mrb.get_args(state, "o", &arr)

	if !mrb.array_p(arr) {
		return mrb.raise_error(state, "ArgumentError", "poly(verts): argument must be an Array of Vector2")
	}

	n := int(mrb.ary_len(arr))
	if n < 3 {
		return mrb.raise_error(state, "ArgumentError", "poly(verts): need at least 3 vertices")
	}

	tmp := make([dynamic]rl.Vector2, 0, n, context.temp_allocator)
	for i in 0 ..< n {
		v := mrb.ary_entry(arr, i32(i))
		vp := extract_native(rl.Vector2, v)
		if vp == nil {
			return mrb.raise_error(state, "ArgumentError", "poly(verts): element is not a Vector2")
		}
		append(&tmp, vp^)
	}

	return create_poly(tmp[:])
}

ruby_poly_verts :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Poly, self)
	if p == nil { return mrb.NIL }
	arr := mrb.ary_new(state)
	for v in p.verts { mrb.ary_push(state, arr, create_vector2(v)) }
	return arr
}

ruby_poly_count :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Poly, self)
	n: mrb.Int = 0 if p == nil else mrb.Int(len(p.verts))
	return mrb.fixnum_value(n)
}

ruby_poly_contains :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pt_val: mrb.Value
	mrb.get_args(state, "o", &pt_val)
	p := extract_native(Poly, self)
	pt := extract_native(rl.Vector2, pt_val)
	if p == nil || pt == nil { return mrb.FALSE }
	return point_in_polygon(pt^, p.verts[:]) ? mrb.TRUE : mrb.FALSE
}

// Ray-casting point-in-polygon (odd winding count -> inside).
@(private = "file")
point_in_polygon :: proc(pt: rl.Vector2, poly: []rl.Vector2) -> bool {
	inside := false
	n := len(poly)
	j := n - 1
	for i in 0 ..< n {
		a := poly[i]
		b := poly[j]
		if (a.y > pt.y) != (b.y > pt.y) {
			x_hit := a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if pt.x < x_hit { inside = !inside }
		}
		j = i
	}
	return inside
}

ruby_poly_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	p := extract_native(Poly, self)
	if p == nil || len(p.verts) < 3 { return mrb.NIL }

	draw_polygon(
		verts = p.verts[:],
		offset = _parse_offset_kwarg(state, kwargs),
		color = _parse_color_kwarg(state, kwargs),
		thickness = _parse_f32_kwarg(state, kwargs, sym.thickness, 1),
		filled = _parse_bool_kwarg(state, kwargs, sym.filled),
		clip = _parse_clip_kwarg(state, kwargs),
	)
	return mrb.NIL
}

ruby_poly_add :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	p := extract_native(Poly, self)
	v := extract_native(rl.Vector2, other)
	if p == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Poly#+ expects a Vector2") }
	tmp := make([dynamic]rl.Vector2, 0, len(p.verts), context.temp_allocator)
	for vert in p.verts { append(&tmp, vert + v^) }
	return create_poly(tmp[:])
}

ruby_poly_subtract :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other: mrb.Value
	mrb.get_args(state, "o", &other)
	p := extract_native(Poly, self)
	v := extract_native(rl.Vector2, other)
	if p == nil { return mrb.NIL }
	if v == nil { return mrb.raise_error(state, "ArgumentError", "Poly#- expects a Vector2") }
	tmp := make([dynamic]rl.Vector2, 0, len(p.verts), context.temp_allocator)
	for vert in p.verts { append(&tmp, vert - v^) }
	return create_poly(tmp[:])
}

setup_poly :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Poly")
	mrb.define_method(g.mrb_state, c, "+", cast(rawptr)ruby_poly_add, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "-", cast(rawptr)ruby_poly_subtract, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "verts", cast(rawptr)ruby_poly_verts, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "count", cast(rawptr)ruby_poly_count, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "contains?", cast(rawptr)ruby_poly_contains, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_poly_draw, mrb.ARGS_OPT(1))

}

draw_polygon :: proc(
	verts: []rl.Vector2,
	offset: rl.Vector2 = {0, 0},
	color: rl.Color = {255, 255, 255, 255},
	thickness: f32 = 1,
	filled: bool = false,
	clip: Maybe(rl.Rectangle) = nil,
) {
	n := len(verts)
	if n < 3 { return }

	pts := make([]rl.Vector2, n, context.temp_allocator)
	for v, i in verts {
		pts[i] = lin.floor(v + offset)
	}

	did_clip := _clip(clip, pts[0])

	if filled {
		// Ear-clip triangulates any simple polygon (convex or concave) and
		// normalizes winding so Raylib's backface culling in 2D mode doesn't
		// drop CW input.
		tris := _triangulate_ear_clip(pts, context.temp_allocator)
		for t in tris {
			rl.DrawTriangle(t[0], t[1], t[2], color)
		}
	} else {
		for i in 0 ..< n {
			a := pts[i]
			b := pts[(i + 1) % n]
			rl.DrawLineEx(a, b, thickness, color)
		}
	}

	if did_clip { rl.EndScissorMode() }
}

// Shoelace area in screen coords (y-down). Screen-CCW polygons return
// negative — that's the orientation Raylib's 2D backface culling keeps.
@(private = "file")
_screen_signed_area :: proc(verts: []rl.Vector2) -> f32 {
	sum: f32 = 0
	n := len(verts)
	for i in 0 ..< n {
		a := verts[i]
		b := verts[(i + 1) % n]
		sum += a.x * b.y - b.x * a.y
	}
	return sum * 0.5
}

@(private = "file")
_point_in_triangle :: proc(p, a, b, c: rl.Vector2) -> bool {
	d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	has_neg := (d1 < 0) || (d2 < 0) || (d3 < 0)
	has_pos := (d1 > 0) || (d2 > 0) || (d3 > 0)
	return !(has_neg && has_pos)
}

// Ear-clipping triangulation. O(n²). Handles any simple polygon.
// Normalizes to screen-CCW so emitted triangles survive Raylib's culling.
_triangulate_ear_clip :: proc(verts: []rl.Vector2, allocator := context.temp_allocator) -> [][3]rl.Vector2 {
	context.allocator = allocator
	n := len(verts)
	if n < 3 { return nil }

	pts := make([dynamic]rl.Vector2, 0, n)
	if _screen_signed_area(verts) > 0 {
		// input is screen-CW; reverse to screen-CCW
		for i := n - 1; i >= 0; i -= 1 { append(&pts, verts[i]) }
	} else {
		for v in verts { append(&pts, v) }
	}

	tris := make([dynamic][3]rl.Vector2, 0, n - 2)

	// Guard against pathological input (collinear/degenerate). Max iterations
	// bounded by n - each successful clip removes one vertex.
	guard := 0
	for len(pts) > 3 && guard < n * n {
		guard += 1
		m := len(pts)
		found := false
		for i in 0 ..< m {
			pi := (i - 1 + m) % m
			ni := (i + 1) % m
			a := pts[pi]
			b := pts[i]
			c := pts[ni]

			// convex vertex under screen-CCW winding -> cross < 0
			cross := (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
			if cross >= 0 { continue }

			// no other poly vert inside triangle abc?
			ok := true
			for j in 0 ..< m {
				if j == pi || j == i || j == ni { continue }
				if _point_in_triangle(pts[j], a, b, c) { ok = false; break }
			}
			if !ok { continue }

			append(&tris, [3]rl.Vector2{a, b, c})
			ordered_remove(&pts, i)
			found = true
			break
		}
		if !found { break } 	// degenerate; bail rather than loop forever
	}

	if len(pts) == 3 {
		append(&tris, [3]rl.Vector2{pts[0], pts[1], pts[2]})
	}

	return tris[:]
}
