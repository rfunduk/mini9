package engine

import "base:runtime"
import "core:math"
import b2 "lib:box2d"
import mrb "lib:mruby"
import rl "lib:raylib"
import rv "lib:rove"

NAV_CIRC_SEGMENTS :: 16
// Distance (px) at which the agent is considered to have reached a
// path corner and the cursor advances to the next waypoint. Keeps the
// agent from snapping to every corner; small enough to feel responsive.
NAV_HYSTERESIS :: f32(1.5)
// Distance (px) at which `arrived?` flips true for the final goal.
NAV_ARRIVED_EPS :: f32(0.5)
// Distance (px) from the current path segment at which the agent is
// considered to have drifted off-path and triggers a replan.
NAV_DRIFT :: f32(32.0)
// AABB bounds for the "whole world" Box2D query when rebuilding the
// navmesh. Must exceed the playable area by a wide margin in any game.
NAV_WORLD_AABB :: f32(1e9)

// Registry of live navigators for engine-side debug overlay.
@(private = "file")
navigators: [dynamic]^Navigator

Navigator :: struct {
	bounds:       [dynamic]rl.Vector2,
	holes_static: [dynamic][dynamic]rl.Vector2,
	mask:         u64,
	margin:       f32,
	mesh:         rv.Mesh,
	has_mesh:     bool,
	target:       rl.Vector2,
	has_target:   bool,
	path:         [dynamic]rl.Vector2,
	cursor:       int,
	path_dirty:   bool,
	snap:         f32,
	parent:       mrb.Value,
}

ruby_navigator_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr == nil { return }
	n := cast(^Navigator)ptr
	for nav, i in navigators {
		if nav == n {
			unordered_remove(&navigators, i)
			break
		}
	}
	if n.parent != mrb.NIL { mrb.gc_unregister(state, n.parent) }
	delete(n.bounds)
	for h in n.holes_static { delete(h) }
	delete(n.holes_static)
	delete(n.path)
	if n.has_mesh { rv.destroy(&n.mesh) }
	mrb.free(state, ptr)
}

// RUBY FUNCTION: navigator(bounds:, mask:, holes: nil, margin: 0)
// @engine_method: name="navigator", aspec=ARGS_REQ(1)
ruby_nav :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "H", &kwargs)

	bounds_val := mrb.kwarg(state, kwargs, sym.bounds)
	if bounds_val == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "navigator: `bounds:` is required")
	}

	mask_val := mrb.kwarg(state, kwargs, sym.mask)
	mask := layer_to_bitmask(state, mask_val)

	margin: f32 = 0
	if v := mrb.kwarg(state, kwargs, sym.margin); v != mrb.NIL {
		margin = f32(mrb.to_f64(v))
	}

	n := Navigator {
		parent = mrb.NIL,
		mask   = mask,
		margin = margin,
	}

	if !shape_to_verts(state, bounds_val, &n.bounds) {
		delete(n.bounds)
		return mrb.raise_error(
			state,
			"ArgumentError",
			"navigator: `bounds:` must be Array[Vector2], Rect, Circ, or Poly",
		)
	}
	if len(n.bounds) < 3 {
		delete(n.bounds)
		return mrb.raise_error(state, "ArgumentError", "navigator: `bounds:` needs at least 3 vertices")
	}

	holes_val := mrb.kwarg(state, kwargs, sym.holes)
	if holes_val != mrb.NIL {
		if !mrb.array_p(holes_val) {
			cleanup_new_navigator(&n)
			return mrb.raise_error(state, "ArgumentError", "navigator: `holes:` must be an Array of shapes")
		}
		hn := int(mrb.ary_len(holes_val))
		for i in 0 ..< hn {
			entry := mrb.ary_entry(holes_val, i32(i))
			hole: [dynamic]rl.Vector2
			if !shape_to_verts(state, entry, &hole) {
				delete(hole)
				cleanup_new_navigator(&n)
				return mrb.raise_error(
					state,
					"ArgumentError",
					"navigator: hole element must be Array[Vector2], Rect, Circ, or Poly",
				)
			}
			if len(hole) >= 3 {
				append(&n.holes_static, hole)
			} else {
				delete(hole)
			}
		}
	}

	ptr := mrb.alloc(g.mrb_state, n)
	class := mrb.class_get(g.mrb_state, "Navigator")
	ruby_obj := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Navigator])

	append(&navigators, ptr)
	if !nav_rebuild_mesh(ptr) {
		return mrb.raise_error(
			state,
			"RuntimeError",
			"navigator: failed to tessellate navmesh — check bounds/holes for degenerate or self-intersecting geometry",
		)
	}
	return ruby_obj
}

@(private = "file")
cleanup_new_navigator :: proc(n: ^Navigator) {
	delete(n.bounds)
	for h in n.holes_static { delete(h) }
	delete(n.holes_static)
}

// Shape-to-verts dispatcher. Returns false on unsupported type (caller frees dst).
shape_to_verts :: proc(state: mrb.State, val: mrb.Value, dst: ^[dynamic]rl.Vector2) -> bool {
	if mrb.array_p(val) {
		n := int(mrb.ary_len(val))
		reserve(dst, len(dst) + n)
		for i in 0 ..< n {
			v := mrb.ary_entry(val, i32(i))
			vp := extract_native(rl.Vector2, v)
			if vp == nil { return false }
			append(dst, vp^)
		}
		return true
	}
	if is_native(rl.Rectangle, val) {
		r := extract_native(rl.Rectangle, val)
		if r == nil { return false }
		append(dst, rl.Vector2{r.x, r.y})
		append(dst, rl.Vector2{r.x + r.width, r.y})
		append(dst, rl.Vector2{r.x + r.width, r.y + r.height})
		append(dst, rl.Vector2{r.x, r.y + r.height})
		return true
	}
	if is_native(Circ, val) {
		c := extract_native(Circ, val)
		if c == nil { return false }
		reserve(dst, len(dst) + NAV_CIRC_SEGMENTS)
		for i in 0 ..< NAV_CIRC_SEGMENTS {
			theta := f32(i) * 2 * math.PI / NAV_CIRC_SEGMENTS
			append(dst, rl.Vector2{c.center.x + c.r * math.cos(theta), c.center.y + c.r * math.sin(theta)})
		}
		return true
	}
	if is_native(Poly, val) {
		p := extract_native(Poly, val)
		if p == nil { return false }
		reserve(dst, len(dst) + len(p.verts))
		for v in p.verts { append(dst, v) }
		return true
	}
	return false
}

// Internal: rebuild rove mesh from bounds + static holes + Box2D extraction.
// On libtess failure the Navigator retains its previous mesh (if any) and the
// caller's Ruby code sees an unchanged navmesh — better than silently losing
// pathfinding mid-game. `recalculate` from Ruby surfaces the error.
@(private = "file")
nav_rebuild_mesh :: proc(n: ^Navigator) -> bool {
	all_holes: [dynamic][]rv.Vec2
	all_holes.allocator = context.temp_allocator
	for &h in n.holes_static { append(&all_holes, h[:]) }

	if n.mask != 0 {
		box2d_holes := extract_box2d_obstacles(n.mask, context.temp_allocator)
		for h in box2d_holes { append(&all_holes, h) }
	}

	// Apply agent margin:
	//   holes grow outward (agent keeps clear of each obstacle)
	//   bounds shrinks inward (agent keeps clear of outer walls)
	bounds_inset := make([]rl.Vector2, len(n.bounds), context.temp_allocator)
	copy(bounds_inset, n.bounds[:])
	if n.margin > 0 {
		for &h in all_holes { inflate_polygon(h, n.margin) }
		inflate_polygon(bounds_inset, -n.margin)
	}

	// Build first, swap second — on failure the existing mesh stays live.
	new_mesh, ok := rv.build(bounds_inset, all_holes[:])
	if !ok { return false }

	if n.has_mesh { rv.destroy(&n.mesh) }
	n.mesh = new_mesh
	n.has_mesh = true
	clear(&n.path)
	return true
}

// Inflate a convex polygon outward by `margin` units along each edge's
// outward normal (uniform offset — every edge shifts by exactly `margin`).
// Each vertex moves along the bisector of its two adjacent edge normals,
// scaled by `margin / sin(interior_angle / 2)` so both edges land at the
// correct offset. Mutates in place.
@(private = "file")
inflate_polygon :: proc(poly: []rv.Vec2, margin: f32) {
	n := len(poly)
	if n < 3 || margin == 0 { return }

	// Determine polygon winding so we know which perpendicular is "outward".
	// Shoelace > 0 in math coords = CCW. For CCW edge (a->b), outward normal
	// points to the right of travel (dy, -dx). Flip for CW.
	sum: f32 = 0
	for i in 0 ..< n {
		a := poly[i]
		b := poly[(i + 1) % n]
		sum += (b.x - a.x) * (b.y + a.y)
	}
	ccw := sum < 0

	// Per-edge outward unit normals.
	normals := make([][2]f32, n, context.temp_allocator)
	for i in 0 ..< n {
		a := poly[i]
		b := poly[(i + 1) % n]
		dx := b.x - a.x
		dy := b.y - a.y
		l := math.sqrt(dx * dx + dy * dy)
		if l < 1e-6 {
			normals[i] = {0, 0}
			continue
		}
		nx := dy / l
		ny := -dx / l
		if !ccw { nx = -nx; ny = -ny }
		normals[i] = {nx, ny}
	}

	// Offset each vertex along the bisector of its two incident edge normals.
	// If sin(θ/2) is tiny (near-straight vertex) fall back to the normal itself.
	out := make([][2]f32, n, context.temp_allocator)
	for i in 0 ..< n {
		prev_i := (i - 1 + n) % n
		n1 := normals[prev_i]
		n2 := normals[i]
		bx := n1[0] + n2[0]
		by := n1[1] + n2[1]
		blen := math.sqrt(bx * bx + by * by)
		if blen < 1e-6 {
			out[i] = {poly[i].x + n2[0] * margin, poly[i].y + n2[1] * margin}
			continue
		}
		// Solve v = k·(n1+n2) with v·n1 = margin and v·n2 = margin.
		// Gives k = 2·margin / |n1+n2|². Rectangle corner (|b|²=2) -> k=margin,
		// offset magnitude = margin·√2 along diagonal -> each edge shifts by margin.
		k := 2 * margin / (blen * blen)
		out[i] = {poly[i].x + bx * k, poly[i].y + by * k}
	}
	for i in 0 ..< n { poly[i] = out[i] }
}

@(private = "file")
Nav_Extract_Ctx :: struct {
	holes:     ^[dynamic][]rv.Vec2,
	allocator: runtime.Allocator,
}

@(private = "file")
extract_box2d_obstacles :: proc(mask: u64, allocator: runtime.Allocator) -> [][]rv.Vec2 {
	world := physics_world_id()
	if !b2.World_IsValid(world) { return nil }

	aabb := b2.AABB {
		lowerBound = {-NAV_WORLD_AABB, -NAV_WORLD_AABB},
		upperBound = {NAV_WORLD_AABB, NAV_WORLD_AABB},
	}
	filter := b2.DefaultQueryFilter()
	filter.categoryBits = 0xFFFFFFFFFFFFFFFF
	filter.maskBits = mask

	out: [dynamic][]rv.Vec2
	out.allocator = allocator

	ctx := Nav_Extract_Ctx {
		holes     = &out,
		allocator = allocator,
	}
	_ = b2.World_OverlapAABB(world, aabb, filter, nav_overlap_callback, &ctx)
	return out[:]
}

@(private = "file")
nav_overlap_callback :: proc "c" (shape_id: b2.ShapeId, ctx_ptr: rawptr) -> bool {
	context = global_context
	c := cast(^Nav_Extract_Ctx)ctx_ptr

	shape_type := b2.Shape_GetType(shape_id)
	body_id := b2.Shape_GetBody(shape_id)
	tx := b2.Body_GetTransform(body_id)

	switch shape_type {
	case .polygonShape:
		poly := b2.Shape_GetPolygon(shape_id)
		count := int(poly.count)
		verts := make([]rv.Vec2, count, c.allocator)
		for i in 0 ..< count {
			verts[i] = b2.TransformPoint(tx, poly.vertices[i])
		}
		append(c.holes, verts)
	case .circleShape:
		circ := b2.Shape_GetCircle(shape_id)
		verts := make([]rv.Vec2, NAV_CIRC_SEGMENTS, c.allocator)
		for i in 0 ..< NAV_CIRC_SEGMENTS {
			theta := f32(i) * 2 * math.PI / NAV_CIRC_SEGMENTS
			lp := b2.Vec2 {
				circ.center.x + circ.radius * math.cos(theta),
				circ.center.y + circ.radius * math.sin(theta),
			}
			verts[i] = b2.TransformPoint(tx, lp)
		}
		append(c.holes, verts)
	case .capsuleShape, .segmentShape, .chainSegmentShape:
	// TODO(nav): capsule bodies (often char controllers) don't contribute
	// to the navmesh, so agents will path through them. Segments/chains
	// are typically level geometry edges — usually already covered by
	// static `holes:` bounds. Approximate capsule as two circles + box
	// once we have a real game exercising this.
	}
	return true
}

// ── methods ──────────────────────────────────────────────────────────────

@(private = "file")
get_parent_pos :: proc(n: ^Navigator) -> (rl.Vector2, bool) {
	if n.parent == mrb.NIL { return {}, false }
	go := extract_native(Game_Object, n.parent)
	if go == nil { return {}, false }
	vp := extract_native(rl.Vector2, go.pos)
	if vp == nil { return {}, false }
	return vp^, true
}

// Recompute path from parent position toward target. Called only when the
// path is dirty (new target / recalculate / player drifted off-path) — not
// every frame, to avoid oscillation at corners from numeric jitter.
@(private = "file")
nav_update_path :: proc(n: ^Navigator) {
	clear(&n.path)
	n.cursor = 0
	if !n.has_mesh || !n.has_target { return }
	parent_pos, ok := get_parent_pos(n)
	if !ok { return }

	result := rv.find_path(&n.mesh, parent_pos, n.target, context.temp_allocator)
	reserve(&n.path, len(result))
	for v in result { append(&n.path, v) }
	n.path_dirty = false
}

// Navigator._attach(parent) — auto-called by obj() for fields responding to :_attach
ruby_nav_attach :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	this_obj: mrb.Value
	mrb.get_args(state, "o", &this_obj)

	n := extract_native(Navigator, self)
	if n == nil { return mrb.NIL }

	// Setting the same parent again is a no-op — avoid churning GC refcounts.
	if n.parent == this_obj { return self }

	if n.parent != mrb.NIL { mrb.gc_unregister(state, n.parent) }
	n.parent = this_obj
	if this_obj != mrb.NIL { mrb.gc_register(state, this_obj) }
	return self
}

ruby_nav_set_target :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	val: mrb.Value
	mrb.get_args(state, "o", &val)
	n := extract_native(Navigator, self)
	if n == nil { return val }
	vp := extract_native(rl.Vector2, val)
	if vp == nil {
		return mrb.raise_error(state, "TypeError", "navigator.target= expects a Vector2")
	}
	t := vp^
	// Clamp to walkable: if point falls in a hole / outside mesh, snap to
	// nearest point on the mesh boundary. Feels natural — target sits on
	// the closest walkable pixel, not some triangle's centroid.
	if n.has_mesh { t = rv.nearest_walkable_point(&n.mesh, t) }
	// Only dirty the path if target actually moved. Repeated `target=` with
	// the same value (e.g. `down?(:left_mouse)` holding) stays stable.
	changed := !n.has_target || n.target != t
	n.target = t
	n.has_target = true
	if changed { n.path_dirty = true }
	return val
}

ruby_nav_get_target :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil || !n.has_target { return mrb.NIL }
	return create_vector2(n.target)
}

ruby_nav_next_position :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return mrb.NIL }
	parent_pos, ok := get_parent_pos(n)
	if !ok { return create_vector2({}) }

	// Replan if path dirty, empty, OR agent has strayed off the walkable
	// mesh (into a hole). Stale paths produce straight-line steps that cut
	// through obstacles when the agent shouldn't be there in the first place.
	if n.path_dirty || len(n.path) == 0 { nav_update_path(n) }

	// Advance cursor while we're within hysteresis of the current corner.
	for n.cursor < len(n.path) - 1 {
		target_corner := n.path[n.cursor + 1]
		d := target_corner - parent_pos
		if d.x * d.x + d.y * d.y > NAV_HYSTERESIS * NAV_HYSTERESIS { break }
		n.cursor += 1
	}

	// If parent drifted far from the active segment, replan.
	if len(n.path) >= 2 && n.cursor < len(n.path) - 1 {
		curr := n.path[n.cursor]
		d := curr - parent_pos
		if d.x * d.x + d.y * d.y > NAV_DRIFT * NAV_DRIFT {
			n.path_dirty = true
			nav_update_path(n)
		}
	}

	// Pick where to move next.
	//   path empty -> unreachable (target sits in a disconnected region, e.g.
	//     a collider fully splits the bounds). Stand still rather than
	//     marching in a straight line through the obstacle.
	//   path >= 2 -> follow corners.
	out := parent_pos
	if len(n.path) >= 2 {
		idx := n.cursor + 1
		if idx >= len(n.path) { idx = len(n.path) - 1 }
		out = n.path[idx]
	}

	if n.snap > 0 {
		out.x = math.round(out.x / n.snap) * n.snap
		out.y = math.round(out.y / n.snap) * n.snap
	}
	return create_vector2(out)
}

ruby_nav_path :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return mrb.NIL }
	arr := mrb.ary_new(state)
	for v in n.path { mrb.ary_push(state, arr, create_vector2(v)) }
	return arr
}

// Cheap len(path) without rebuilding the Ruby Array + per-waypoint Vector2
// objects — used by `to_s` / debug inspection in hot paths.
ruby_nav_path_count :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return mrb.fixnum_value(0) }
	return mrb.fixnum_value(mrb.Int(len(n.path)))
}

ruby_nav_arrived :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return mrb.TRUE }
	if !n.has_target || len(n.path) == 0 { return mrb.TRUE }
	parent_pos, ok := get_parent_pos(n)
	if !ok { return mrb.FALSE }
	last := n.path[len(n.path) - 1]
	d := last - parent_pos
	return (d.x * d.x + d.y * d.y <= NAV_ARRIVED_EPS * NAV_ARRIVED_EPS) ? mrb.TRUE : mrb.FALSE
}

ruby_nav_recalculate :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return self }
	if !nav_rebuild_mesh(n) {
		return mrb.raise_error(state, "RuntimeError", "navigator.recalculate: failed to tessellate navmesh")
	}
	n.path_dirty = true
	return self
}

ruby_nav_set_snap :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	n := extract_native(Navigator, self)
	if n != nil { n.snap = f32(v) }
	return mrb.word_boxing_float_value(state, v)
}

ruby_nav_get_snap :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	return mrb.word_boxing_float_value(state, n == nil ? 0 : f64(n.snap))
}

// Engine-side debug overlay — translucent Godot-style navmesh visualization.
ruby_nav_draw_debug :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	n := extract_native(Navigator, self)
	if n == nil { return self }

	fill_col := rl.Color{80, 200, 255, 40}
	edge_col := rl.Color{80, 200, 255, 180}
	path_col := rl.Color{255, 240, 60, 220}
	target_col := rl.Color{255, 80, 80, 255}

	if n.has_mesh {
		for tri in n.mesh.tris {
			a := n.mesh.verts[tri[0]]
			b := n.mesh.verts[tri[1]]
			c := n.mesh.verts[tri[2]]
			rl.DrawTriangle(a, b, c, fill_col)
			rl.DrawLineV(a, b, edge_col)
			rl.DrawLineV(b, c, edge_col)
			rl.DrawLineV(c, a, edge_col)
		}
	}
	if len(n.path) > 1 {
		for i in 0 ..< len(n.path) - 1 {
			rl.DrawLineEx(n.path[i], n.path[i + 1], 1, path_col)
		}
		for p in n.path {
			rl.DrawCircleV(p, 1.5, path_col)
		}
	}
	if n.has_target { rl.DrawCircleV(n.target, 2, target_col) }

	return self
}

cleanup_navigation :: proc() {
	delete(navigators)
	navigators = nil
}

setup_navigation :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Navigator")
	mrb.define_method(g.mrb_state, c, "_attach", cast(rawptr)ruby_nav_attach, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "target=", cast(rawptr)ruby_nav_set_target, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "target", cast(rawptr)ruby_nav_get_target, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "next_position", cast(rawptr)ruby_nav_next_position, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "path", cast(rawptr)ruby_nav_path, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "path_count", cast(rawptr)ruby_nav_path_count, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "arrived?", cast(rawptr)ruby_nav_arrived, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "recalculate", cast(rawptr)ruby_nav_recalculate, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "snap=", cast(rawptr)ruby_nav_set_snap, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "snap", cast(rawptr)ruby_nav_get_snap, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "draw_debug", cast(rawptr)ruby_nav_draw_debug, mrb.ARGS_NONE)
}
