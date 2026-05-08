package rove_tests

import "core:math"
import "core:testing"
import rv "lib:rove"

@(test)
test_build_square :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)
	testing.expect(t, len(m.verts) >= 4)
	testing.expect_value(t, len(m.tris), 2)
	testing.expect_value(t, len(m.adj), 2)
	expect_adj_symmetric(t, m)
}

@(test)
test_build_l_shape :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {20, 0}, {20, 10}, {10, 10}, {10, 20}, {0, 20}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)
	testing.expect_value(t, len(m.tris), 4)
	expect_adj_symmetric(t, m)
}

@(test)
test_build_square_with_hole :: proc(t: ^testing.T) {
	bounds := []rv.Vec2{{0, 0}, {40, 0}, {40, 40}, {0, 40}}
	hole := []rv.Vec2{{15, 15}, {25, 15}, {25, 25}, {15, 25}}
	m, _ := rv.build(bounds, {hole})
	defer rv.destroy(&m)

	testing.expect(t, len(m.tris) >= 6)

	// Inside the hole: locate should fail.
	_, ok := rv.locate(&m, rv.Vec2{20, 20})
	testing.expect(t, !ok)

	// Outside bounds: fail.
	_, ok2 := rv.locate(&m, rv.Vec2{-5, 20})
	testing.expect(t, !ok2)

	// Walkable annulus: succeed.
	_, ok3 := rv.locate(&m, rv.Vec2{5, 20})
	testing.expect(t, ok3)

	expect_adj_symmetric(t, m)
}

@(test)
test_build_hole_touching_bounds :: proc(t: ^testing.T) {
	// Hole shares left edge with bounds — the case that killed earclip.
	bounds := []rv.Vec2{{0, 0}, {40, 0}, {40, 40}, {0, 40}}
	hole := []rv.Vec2{{0, 15}, {20, 15}, {20, 25}, {0, 25}}
	m, _ := rv.build(bounds, {hole})
	defer rv.destroy(&m)

	testing.expect(t, len(m.tris) > 0)

	// Inside hole region: fail.
	_, ok := rv.locate(&m, rv.Vec2{10, 20})
	testing.expect(t, !ok)

	// Walkable above hole: succeed.
	_, ok2 := rv.locate(&m, rv.Vec2{10, 5})
	testing.expect(t, ok2)

	expect_adj_symmetric(t, m)
}

@(test)
test_build_hole_past_bounds :: proc(t: ^testing.T) {
	// Hole extends past bounds on the left.
	bounds := []rv.Vec2{{0, 0}, {40, 0}, {40, 40}, {0, 40}}
	hole := []rv.Vec2{{-10, 15}, {20, 15}, {20, 25}, {-10, 25}}
	m, _ := rv.build(bounds, {hole})
	defer rv.destroy(&m)

	testing.expect(t, len(m.tris) > 0)

	// Inside hole (inside bounds portion): fail.
	_, ok := rv.locate(&m, rv.Vec2{10, 20})
	testing.expect(t, !ok)

	// Walkable region: succeed.
	_, ok2 := rv.locate(&m, rv.Vec2{30, 20})
	testing.expect(t, ok2)

	expect_adj_symmetric(t, m)
}

@(test)
test_locate_inside_square :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	tri, ok := rv.locate(&m, rv.Vec2{5, 5})
	testing.expect(t, ok)
	testing.expect(t, tri >= 0 && tri < len(m.tris))
}

@(test)
test_locate_outside_returns_false :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	_, ok := rv.locate(&m, rv.Vec2{100, 100})
	testing.expect(t, !ok)
}

@(test)
test_find_path_same_tri :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{1, 1}, rv.Vec2{2, 2})
	defer delete(path)
	testing.expect_value(t, len(path), 2)
	testing.expect_value(t, path[0], rv.Vec2{1, 1})
	testing.expect_value(t, path[1], rv.Vec2{2, 2})
}

@(test)
test_find_path_straight_square :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{1, 1}, rv.Vec2{9, 9})
	defer delete(path)
	testing.expect_value(t, len(path), 2)
	testing.expect_value(t, path[0], rv.Vec2{1, 1})
	testing.expect_value(t, path[len(path) - 1], rv.Vec2{9, 9})
}

@(test)
test_find_path_l_shape_turns_at_corner :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {20, 0}, {20, 10}, {10, 10}, {10, 20}, {0, 20}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{18, 2}, rv.Vec2{2, 18})
	defer delete(path)
	testing.expect(t, len(path) >= 3)
	testing.expect_value(t, path[0], rv.Vec2{18, 2})
	testing.expect_value(t, path[len(path) - 1], rv.Vec2{2, 18})

	// Length sanity. Direct distance ≈ 22.6, corner-detour ≈ 21, allow 25.
	total: f32 = 0
	for i in 1 ..< len(path) {
		d := path[i] - path[i - 1]
		total += math.sqrt(d.x * d.x + d.y * d.y)
	}
	testing.expect(t, total < 25)
}

@(test)
test_find_path_around_hole :: proc(t: ^testing.T) {
	bounds := []rv.Vec2{{0, 0}, {40, 0}, {40, 40}, {0, 40}}
	hole := []rv.Vec2{{15, 15}, {25, 15}, {25, 25}, {15, 25}}
	m, _ := rv.build(bounds, {hole})
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{5, 20}, rv.Vec2{35, 20})
	defer delete(path)
	testing.expect(t, len(path) >= 3)
	testing.expect_value(t, path[0], rv.Vec2{5, 20})
	testing.expect_value(t, path[len(path) - 1], rv.Vec2{35, 20})

	// Total path length sane (< 35 for a direct distance 30).
	total: f32 = 0
	for i in 1 ..< len(path) {
		d := path[i] - path[i - 1]
		total += math.sqrt(d.x * d.x + d.y * d.y)
	}
	testing.expect(t, total < 35)
}

@(test)
test_find_path_outside_falls_back :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{-5, -5}, rv.Vec2{5, 5})
	defer delete(path)
	testing.expect(t, len(path) >= 2)
}

@(test)
test_destroy_zeros_mesh :: proc(t: ^testing.T) {
	m: rv.Mesh
	append(&m.verts, rv.Vec2{1, 2})
	append(&m.tris, rv.Tri{0, 0, 0})
	append(&m.adj, [3]int{-1, -1, -1})
	rv.destroy(&m)
	testing.expect_value(t, len(m.verts), 0)
	testing.expect_value(t, len(m.tris), 0)
	testing.expect_value(t, len(m.adj), 0)
}

// Guards against funnel portal-orientation bugs: with a tight obstacle
// wedged between start and goal, the only valid path has a real corner.
// If the funnel picks the wrong side (math-vs-screen CCW confusion) every
// intermediate waypoint should land inside the hole — we assert they're
// walkable and that path length is plausible for a detour around a thick
// pillar (direct distance 30, optimal detour ≈ 31.66).
@(test)
test_find_path_around_tight_pillar :: proc(t: ^testing.T) {
	bounds := []rv.Vec2{{0, 0}, {40, 0}, {40, 40}, {0, 40}}
	// Pillar occupies the full vertical center, leaving a 5-unit corridor
	// above and below. Agent must route around top or bottom.
	hole := []rv.Vec2{{10, 17}, {30, 17}, {30, 23}, {10, 23}}
	m, ok := rv.build(bounds, {hole})
	testing.expect(t, ok, "tessellation must succeed")
	defer rv.destroy(&m)

	path := rv.find_path(&m, rv.Vec2{5, 20}, rv.Vec2{35, 20})
	defer delete(path)
	testing.expect(t, len(path) >= 3, "path must turn around the pillar")

	// Every interior waypoint must be walkable (not inside the hole).
	// Skip first + last — those were snapped to nearest walkable on entry.
	for i in 1 ..< len(path) - 1 {
		_, hit := rv.locate(&m, path[i])
		testing.expectf(
			t,
			hit,
			"waypoint %d at %v fell inside hole — portal orientation likely wrong",
			i,
			path[i],
		)
	}

	total: f32 = 0
	for i in 1 ..< len(path) {
		d := path[i] - path[i - 1]
		total += math.sqrt(d.x * d.x + d.y * d.y)
	}
	// Optimal detour: (5,20) -> (10,17) -> (30,17) -> (35,20) ≈ 31.66.
	// Upper bound catches gross failures (e.g. a path that wraps the wrong
	// way around the mesh).
	testing.expectf(t, total > 31 && total < 40, "path length %v outside sane detour range [31, 40]", total)
}

@(test)
test_find_path_unreachable_on_disconnected_mesh :: proc(t: ^testing.T) {
	// Hand-built mesh with two disconnected triangles (no shared edges).
	// build() can't produce this naturally, so we synthesize it.
	m: rv.Mesh
	defer rv.destroy(&m)
	append(&m.verts, rv.Vec2{0, 0}, rv.Vec2{10, 0}, rv.Vec2{5, 10}) // tri 0
	append(&m.verts, rv.Vec2{50, 50}, rv.Vec2{60, 50}, rv.Vec2{55, 60}) // tri 1
	append(&m.tris, rv.Tri{0, 1, 2})
	append(&m.tris, rv.Tri{3, 4, 5})
	append(&m.adj, [3]int{-1, -1, -1})
	append(&m.adj, [3]int{-1, -1, -1})

	// Start in tri 0, goal in tri 1 — no corridor exists.
	path := rv.find_path(&m, rv.Vec2{5, 3}, rv.Vec2{55, 55})
	defer delete(path)
	testing.expect_value(t, len(path), 0)
}

@(test)
test_find_path_empty_mesh :: proc(t: ^testing.T) {
	m: rv.Mesh
	defer rv.destroy(&m)
	path := rv.find_path(&m, rv.Vec2{0, 0}, rv.Vec2{10, 10})
	defer delete(path)
	testing.expect_value(t, len(path), 0)
}

@(test)
test_find_path_start_equals_goal :: proc(t: ^testing.T) {
	poly := []rv.Vec2{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	m, _ := rv.build(poly)
	defer rv.destroy(&m)
	p := rv.Vec2{5, 5}
	path := rv.find_path(&m, p, p)
	defer delete(path)
	testing.expect_value(t, len(path), 2)
	testing.expect_value(t, path[0], p)
	testing.expect_value(t, path[1], p)
}

@(test)
test_build_degenerate_returns_ok_false :: proc(t: ^testing.T) {
	// Fewer than 3 verts -> can't tessellate.
	poly := []rv.Vec2{{0, 0}, {1, 0}}
	m, ok := rv.build(poly)
	defer rv.destroy(&m)
	testing.expect(t, !ok, "degenerate bounds should report failure")
	testing.expect_value(t, len(m.tris), 0)
}

@(private = "file")
expect_adj_symmetric :: proc(t: ^testing.T, m: rv.Mesh, loc := #caller_location) {
	for row, t_idx in m.adj {
		for n, e in row {
			if n == -1 { continue }
			found := false
			for back_n in m.adj[n] {
				if back_n == t_idx {
					found = true
					break
				}
			}
			testing.expectf(
				t,
				found,
				"adj asymmetric: tri %d edge %d -> %d, but %d has no back-ref",
				t_idx,
				e,
				n,
				n,
				loc = loc,
			)
		}
	}
}
