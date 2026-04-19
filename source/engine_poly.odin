package engine

import mrb "lib:mruby"
import rl "vendor:raylib"

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
// @engine_method: name="poly", arity=1
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

// Ray-casting point-in-polygon (odd winding count → inside).
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

setup_poly :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Poly")
	mrb.define_method(g.mrb_state, c, "verts", cast(rawptr)ruby_poly_verts, 0)
	mrb.define_method(g.mrb_state, c, "count", cast(rawptr)ruby_poly_count, 0)
	mrb.define_method(g.mrb_state, c, "contains?", cast(rawptr)ruby_poly_contains, 1)
}
