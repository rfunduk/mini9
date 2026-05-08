package rove

import pq "core:container/priority_queue"
import "core:math"
import "core:slice"

@(private)
Astar_Node :: struct {
	tri: int,
	g:   f32,
	f:   f32,
}

@(private)
astar_node_less :: proc(a, b: Astar_Node) -> bool { return a.f < b.f }

@(private)
astar_node_swap :: proc(q: []Astar_Node, i, j: int) { q[i], q[j] = q[j], q[i] }

// Locate the triangle containing point p. First hit wins on overlap
// (degenerate shared-edge points). Returns (-1, false) if outside mesh.
locate :: proc(m: ^Mesh, p: Vec2) -> (tri_idx: int, ok: bool) {
	for tri, t in m.tris {
		a := m.verts[tri[0]]
		b := m.verts[tri[1]]
		c := m.verts[tri[2]]
		if point_in_tri(p, a, b, c) { return t, true }
	}
	return -1, false
}

// Locate `p` or fall back to the triangle owning the nearest boundary point.
// Ensures a coherent fallback: the returned triangle is actually adjacent to
// the portion of walkable space closest to the query — crucial for funnel
// portal continuity when the agent drifts slightly into a hole.
locate_nearest :: proc(m: ^Mesh, p: Vec2) -> (tri_idx: int, ok: bool) {
	if t, hit := locate(m, p); hit { return t, true }
	_, tri, found := nearest_walkable(m, p)
	return tri, found
}

// Nearest walkable point to p. Returns p itself if already inside a triangle.
// Used to clamp click targets that fall in obstacles or outside bounds.
nearest_walkable_point :: proc(m: ^Mesh, p: Vec2) -> Vec2 {
	if _, hit := locate(m, p); hit { return p }
	pt, _, _ := nearest_walkable(m, p)
	return pt
}

// Joint query: closest walkable point AND the triangle owning that edge.
// Iterates every triangle edge and tracks the minimum.
nearest_walkable :: proc(m: ^Mesh, p: Vec2) -> (pt: Vec2, tri_idx: int, ok: bool) {
	if len(m.tris) == 0 { return p, -1, false }
	best_pt := p
	best_tri := -1
	best_d: f32 = max(f32)
	for tri, t in m.tris {
		a := m.verts[tri[0]]
		b := m.verts[tri[1]]
		c := m.verts[tri[2]]
		candidates := [3]Vec2 {
			closest_on_segment(p, a, b),
			closest_on_segment(p, b, c),
			closest_on_segment(p, c, a),
		}
		for q in candidates {
			ds := dist_sq(q, p)
			if ds < best_d {
				best_d = ds
				best_pt = q
				best_tri = t
			}
		}
	}
	return best_pt, best_tri, best_tri >= 0
}

@(private)
closest_on_segment :: proc(p, a, b: Vec2) -> Vec2 {
	ab := b - a
	ab_len_sq := ab.x * ab.x + ab.y * ab.y
	if ab_len_sq < 1e-12 { return a }
	ap := p - a
	t := (ap.x * ab.x + ap.y * ab.y) / ab_len_sq
	t = clamp(t, 0, 1)
	return a + ab * t
}

// A* over triangle adjacency.
// Cost: centroid->edge-midpoint->centroid (two-hop through shared portal).
//   More faithful to the actual corridor length than plain centroid-to-
//   centroid — picks better corridors on L-shapes with skinny triangles
//   where centroid distance underrates the detour through a portal.
// Heuristic: euclidean centroid->goal (admissible, since any real corridor
//   through portals is ≥ straight-line centroid-to-goal).
// Returns triangle indices start..goal, empty if unreachable or endpoints
// fall outside the mesh. Caller owns the returned slice.
// `scratch` is used for the visited/g_score maps — pass a per-frame or
// per-call scratch allocator; the library does not mandate one.
find_tri_path :: proc(
	m: ^Mesh,
	from, to: Vec2,
	allocator := context.allocator,
	scratch := context.temp_allocator,
) -> []int {
	context.allocator = allocator
	start, ok1 := locate_nearest(m, from)
	goal, ok2 := locate_nearest(m, to)
	if !ok1 || !ok2 { return nil }
	if start == goal {
		out := make([]int, 1)
		out[0] = start
		return out
	}

	open: pq.Priority_Queue(Astar_Node)
	pq.init(&open, astar_node_less, astar_node_swap)
	defer pq.destroy(&open)

	came_from := make(map[int]int, len(m.tris), scratch)
	g_score := make(map[int]f32, len(m.tris), scratch)

	g_score[start] = 0
	pq.push(&open, Astar_Node{start, 0, distance(tri_centroid(m, start), to)})

	for pq.len(open) > 0 {
		current := pq.pop(&open)

		// Stale-pop filter: a cheaper path to this tri was found after we
		// pushed this entry, so skip it. Saves neighbor expansions that
		// would be immediately rejected by the g_score check below anyway.
		if gs, exists := g_score[current.tri]; exists && current.g > gs { continue }

		if current.tri == goal { return reconstruct(came_from, start, goal) }

		c_centroid := tri_centroid(m, current.tri)

		for neighbor, e in m.adj[current.tri] {
			if neighbor == -1 { continue }
			edge_mid := edge_midpoint(m, current.tri, e)
			n_centroid := tri_centroid(m, neighbor)
			step := distance(c_centroid, edge_mid) + distance(edge_mid, n_centroid)
			tentative := current.g + step
			existing, exists := g_score[neighbor]
			if !exists || tentative < existing {
				came_from[neighbor] = current.tri
				g_score[neighbor] = tentative
				f := tentative + distance(n_centroid, to)
				pq.push(&open, Astar_Node{neighbor, tentative, f})
			}
		}
	}
	return nil
}

@(private)
edge_midpoint :: proc(m: ^Mesh, t: int, e: int) -> Vec2 {
	a := m.verts[m.tris[t][e]]
	b := m.verts[m.tris[t][(e + 1) % 3]]
	return (a + b) / 2
}

@(private)
tri_centroid :: proc(m: ^Mesh, t: int) -> Vec2 {
	tri := m.tris[t]
	return (m.verts[tri[0]] + m.verts[tri[1]] + m.verts[tri[2]]) / 3
}

@(private)
distance :: proc(a, b: Vec2) -> f32 {
	d := a - b
	return math.sqrt(d.x * d.x + d.y * d.y)
}

@(private)
reconstruct :: proc(came_from: map[int]int, start, goal: int) -> []int {
	path: [dynamic]int
	current := goal
	for {
		append(&path, current)
		if current == start { break }
		current = came_from[current]
	}
	slice.reverse(path[:])
	return path[:]
}
