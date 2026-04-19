package rove

import lt "libtess"

Vec2 :: [2]f32

// Triangle as three indices into Mesh.verts.
Tri :: [3]int

// Navmesh: shared vertex pool, triangle list, per-triangle adjacency.
// adj[t][e] = neighbor triangle across edge e (0..2), or -1 if boundary.
// Edge e of triangle t spans verts tris[t][e] -> tris[t][(e + 1) % 3].
//
// Dynamic arrays are allocated from `context.allocator` at `build` time and
// carry that allocator in their own header, so `destroy` frees correctly
// regardless of the caller's context.
Mesh :: struct {
	verts: [dynamic]Vec2,
	tris:  [dynamic]Tri,
	adj:   [dynamic][3]int,
}

// Build a navmesh from a walkable polygon and optional hole polygons.
// Uses libtess2's polygon tesselator under the hood — handles shared edges,
// overlapping holes, holes extending past bounds, and self-intersections
// robustly. Winding rule = ODD, so walkable = bounds ⊕ holes.
// Returns (mesh, true) on success, (zero mesh, false) on libtess failure or
// degenerate input. Caller should only trust the result when `ok == true`.
build :: proc(bounds: []Vec2, holes: [][]Vec2 = nil) -> (m: Mesh, ok: bool) {
	if len(bounds) < 3 { return m, false }

	tess := lt.NewTess(nil)
	defer lt.DeleteTess(tess)

	// Bounds adds as CCW (winding +1). Holes are reversed to CW (winding -1)
	// so the POSITIVE rule picks walkable = (inside bounds) ∧ ¬(inside hole).
	// Handles holes touching/past bounds naturally: area outside bounds has
	// winding 0 regardless, never classified walkable.
	lt.AddContour(tess, 2, raw_data(bounds), size_of(Vec2), i32(len(bounds)))
	max_hole_len := 0
	for h in holes { if len(h) > max_hole_len { max_hole_len = len(h) } }
	reversed := make([dynamic]Vec2, max_hole_len, context.temp_allocator)
	for h in holes {
		if len(h) < 3 { continue }
		clear(&reversed)
		for i := len(h) - 1; i >= 0; i -= 1 { append(&reversed, h[i]) }
		lt.AddContour(tess, 2, raw_data(reversed), size_of(Vec2), i32(len(reversed)))
	}

	tess_ok := lt.Tesselate(tess, .POSITIVE, .CONNECTED_POLYGONS, 3, 2, nil)
	if tess_ok == 0 { return m, false }

	vcount := int(lt.GetVertexCount(tess))
	vptr := lt.GetVertices(tess)
	reserve(&m.verts, vcount)
	for i in 0 ..< vcount {
		append(&m.verts, Vec2{vptr[i * 2], vptr[i * 2 + 1]})
	}

	ecount := int(lt.GetElementCount(tess))
	elems := lt.GetElements(tess)
	// CONNECTED_POLYGONS: 3 vert indices + 3 neighbor tri indices per tri.
	// Neighbor n[k] shares edge verts[k] -> verts[(k+1) % 3] — matches our
	// adjacency convention exactly.
	reserve(&m.tris, ecount)
	reserve(&m.adj, ecount)
	for i in 0 ..< ecount {
		base := i * 6
		a := int(elems[base + 0])
		b := int(elems[base + 1])
		c := int(elems[base + 2])
		n0 := int(elems[base + 3])
		n1 := int(elems[base + 4])
		n2 := int(elems[base + 5])
		if a < 0 || b < 0 || c < 0 { continue }
		append(&m.tris, Tri{a, b, c})
		append(&m.adj, [3]int{n0 if n0 >= 0 else -1, n1 if n1 >= 0 else -1, n2 if n2 >= 0 else -1})
	}

	return m, true
}

destroy :: proc(m: ^Mesh) {
	delete(m.verts)
	delete(m.tris)
	delete(m.adj)
	m^ = {}
}

// Basic point-in-triangle used by locate() in astar.odin.
// Inclusive bounds: a point lying exactly on a shared edge matches *both*
// adjacent triangles. `locate` returns the first hit in iteration order,
// so boundary points are deterministic per mesh but not per input — two
// meshes with the same geometry but different triangle order can assign
// the same edge point to different triangles. Harmless for pathfinding
// (both tris are valid start/goal choices, funnel still converges).
@(private)
point_in_tri :: proc(p, a, b, c: Vec2) -> bool {
	d1 := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
	d2 := (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x)
	d3 := (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x)
	has_neg := d1 < 0 || d2 < 0 || d3 < 0
	has_pos := d1 > 0 || d2 > 0 || d3 > 0
	return !(has_neg && has_pos)
}

// Squared distance. Shared helper used by astar + funnel hot paths.
@(private)
dist_sq :: proc(a, b: Vec2) -> f32 {
	d := a - b
	return d.x * d.x + d.y * d.y
}
