package rove

// Find the straight-line corner path from `from` to `to` through mesh.
// Combines A* over triangles + Simple Stupid Funnel Algorithm (Mononen).
// Returns empty slice if endpoints lie outside mesh.
// Caller owns the returned slice. `scratch` is used for A* maps + portal
// buffer; pass a per-frame/per-call scratch allocator.
find_path :: proc(
	m: ^Mesh,
	from, to: Vec2,
	allocator := context.allocator,
	scratch := context.temp_allocator,
) -> []Vec2 {
	context.allocator = allocator

	// Snap both endpoints to nearest walkable points. Handles agents that
	// drift into a hole (e.g. high-speed overshoot) and click targets that
	// land in obstacles. Funnel stays consistent with the navmesh.
	from_pt := nearest_walkable_point(m, from)
	to_pt := nearest_walkable_point(m, to)

	tri_path := find_tri_path(m, from_pt, to_pt, scratch, scratch)
	if len(tri_path) == 0 { return nil }

	if len(tri_path) == 1 {
		out := make([]Vec2, 2)
		out[0] = from_pt
		out[1] = to_pt
		return out
	}

	// Build portal list: one portal per tri-to-tri hop, plus a degenerate
	// final portal at the goal so SSFA closes the funnel onto it.
	portals := make([dynamic][2]Vec2, 0, len(tri_path), scratch)
	for i in 0 ..< len(tri_path) - 1 {
		t := tri_path[i]
		nxt := tri_path[i + 1]
		e := edge_to_neighbor(m, t, nxt)
		assert(
			e >= 0,
			"find_path: adjacency asymmetric — consecutive tris in A* result lack a shared edge",
		)
		// SSFA convention (Mononen): left/right are relative to travel direction,
		// matching his screen-CCW code. In math-CCW tris, the edge vert order
		// maps such that tris[t][e] sits on the SSFA "left".
		left := m.verts[m.tris[t][e]]
		right := m.verts[m.tris[t][(e + 1) % 3]]
		append(&portals, [2]Vec2{left, right})
	}
	append(&portals, [2]Vec2{to_pt, to_pt})

	return funnel(from_pt, portals[:])
}

// Simple Stupid Funnel Algorithm. Portals oriented so portals[i][0] = left,
// portals[i][1] = right relative to travel direction.
// Start is included in output; final portal should be a degenerate {goal, goal}.
funnel :: proc(start: Vec2, portals: [][2]Vec2, allocator := context.allocator) -> []Vec2 {
	context.allocator = allocator
	path: [dynamic]Vec2
	append(&path, start)

	if len(portals) == 0 { return path[:] }

	apex := start
	vleft := portals[0][0]
	vright := portals[0][1]
	apex_idx := 0
	left_idx := 0
	right_idx := 0

	i := 1
	for i < len(portals) {
		left := portals[i][0]
		right := portals[i][1]

		// Right vertex
		if triarea2(apex, vright, right) <= 0 {
			if vec_eq(apex, vright) || triarea2(apex, vleft, right) > 0 {
				vright = right
				right_idx = i
			} else {
				append(&path, vleft)
				apex = vleft
				apex_idx = left_idx
				vleft = apex
				vright = apex
				left_idx = apex_idx
				right_idx = apex_idx
				i = apex_idx + 1
				continue
			}
		}

		// Left vertex
		if triarea2(apex, vleft, left) >= 0 {
			if vec_eq(apex, vleft) || triarea2(apex, vright, left) < 0 {
				vleft = left
				left_idx = i
			} else {
				append(&path, vright)
				apex = vright
				apex_idx = right_idx
				vleft = apex
				vright = apex
				left_idx = apex_idx
				right_idx = apex_idx
				i = apex_idx + 1
				continue
			}
		}

		i += 1
	}

	// Final apex → goal leg. `to` is portals[last][0] = portals[last][1].
	last := portals[len(portals) - 1][0]
	if len(path) == 0 || !vec_eq(path[len(path) - 1], last) {
		append(&path, last)
	}

	// Dedup: funnel can emit the apex multiple times when the agent sits
	// exactly on a portal vertex. Collapse consecutive duplicates.
	// EPS is in mesh units; mini9 navmeshes are pixel-scale (~hundreds of
	// units wide), so 1e-3 ≈ a thousandth of a pixel — well below anything
	// visible or physically meaningful.
	EPS :: f32(1e-3)
	w := 1
	for r in 1 ..< len(path) {
		if dist_sq(path[r], path[w - 1]) > EPS * EPS {
			path[w] = path[r]
			w += 1
		}
	}
	resize(&path, w)
	return path[:]
}

@(private)
edge_to_neighbor :: proc(m: ^Mesh, t, neighbor: int) -> int {
	for n, e in m.adj[t] {
		if n == neighbor { return e }
	}
	return -1
}

@(private)
triarea2 :: proc(a, b, c: Vec2) -> f32 {
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

@(private)
vec_eq :: proc(a, b: Vec2) -> bool {
	return a.x == b.x && a.y == b.y
}
