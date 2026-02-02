package engine

import _ "core:fmt"
import "core:math"
import lin "core:math/linalg"
import mrb "lib:mruby"
import rl "vendor:raylib"

Collision_Layer :: u16

setup_collision :: proc() {
	c := create_data_class("CollisionInfo")
	mrb.define_method(g.mrb_state, c, "point", cast(rawptr)ruby_collision_info_get_point, 0)
	mrb.define_method(g.mrb_state, c, "normal", cast(rawptr)ruby_collision_info_get_normal, 0)
	mrb.define_method(g.mrb_state, c, "t", cast(rawptr)ruby_collision_info_get_t, 0)
	mrb.define_method(g.mrb_state, c, "body", cast(rawptr)ruby_collision_info_get_body, 0)
}

Collision_Info :: struct {
	hit:    bool,
	point:  rl.Vector2,
	normal: rl.Vector2,
	t:      f32,
	sort_t: f32, // squared distance for sorting
	body:   ^Body,
}

ruby_collisioninfo_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_collision_info :: proc(c: Collision_Info) -> mrb.Value {
	c_ptr := ruby_allocate(Collision_Info, c)

	c_class := mrb.class_get(g.mrb_state, "CollisionInfo")
	ruby_obj := mrb.obj_new(g.mrb_state, c_class, 0, nil)

	mrb.data_init(ruby_obj, c_ptr, NATIVE_TO_MRUBY_TYPE[Collision_Info])

	return ruby_obj
}

// RUBY METHOD: collision_info.point -> gets collision point
ruby_collision_info_get_point :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Collision_Info, self)
	if c == nil { return mrb.NIL }
	return create_vector2(c.point)
}

// RUBY METHOD: collision_info.normal -> gets collision normal
ruby_collision_info_get_normal :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Collision_Info, self)
	if c == nil { return mrb.NIL }
	return create_vector2(c.normal)
}

// RUBY METHOD: collision_info.t -> gets t in radians
ruby_collision_info_get_t :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Collision_Info, self)
	if c == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(c.t))
}

// RUBY METHOD: collision_info.object -> gets object that owns the body that was collided with
ruby_collision_info_get_body :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	c := extract_native(Collision_Info, self)
	if c == nil { return mrb.NIL }
	body, ok := g.registered_bodies[c.body]
	return ok ? body : mrb.NIL
}

// RUBY FUNCTION: raycast(origin: v2(0), direction: v2(1, 0), target: rect(10, 10, 20, 20)) -> returns whether the raycast intersects
// @engine_method: name="raycast", arity=3
ruby_raycast :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	origin_val, direction_val, target_val: mrb.Value
	mrb.get_args(state, "ooo", &origin_val, &direction_val, &target_val)

	origin := extract_native(rl.Vector2, origin_val)
	direction := extract_native(rl.Vector2, direction_val)
	target := extract_native(rl.Rectangle, target_val)

	c := ray_vs_rect(origin^, direction^, target^)

	result_array := mrb.ary_new(state)
	mrb.ary_push(state, result_array, c.hit ? mrb.TRUE : mrb.FALSE)
	mrb.ary_push(state, result_array, c.hit ? create_vector2(c.point) : mrb.NIL)
	mrb.ary_push(state, result_array, c.hit ? create_vector2(c.normal) : mrb.NIL)
	mrb.ary_push(state, result_array, c.hit ? mrb.word_boxing_float_value(state, f64(c.t)) : mrb.NIL)

	return result_array
}

point_vs_rect :: proc(p: rl.Vector2, r: rl.Rectangle) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.width && p.y < r.y + r.height
}

rect_vs_rect :: proc(b1, b2: rl.Rectangle) -> bool {
	return(
		b1.x < b2.x + b2.width &&
		b1.x + b1.width > b2.x &&
		b1.y < b2.y + b2.height &&
		b1.y + b1.height > b2.y \
	)
}

ray_vs_rect :: proc(ray_origin, ray_dir: rl.Vector2, target: rl.Rectangle) -> (c: Collision_Info) {
	pos := rl.Vector2{target.x, target.y}
	size := rl.Vector2{target.width, target.height}
	invdir := 1 / ray_dir

	origin := lin.floor(ray_origin)

	t_near := (pos - origin) * invdir
	t_far := (pos + size - origin) * invdir

	// check for NaN/inf values from division by zero
	if math.is_nan(t_near.x) || math.is_nan(t_near.y) || math.is_nan(t_far.x) || math.is_nan(t_far.y) {
		c.hit = false
		return
	}

	if t_near.x > t_far.x { t_near.x, t_far.x = t_far.x, t_near.x }
	if t_near.y > t_far.y { t_near.y, t_far.y = t_far.y, t_near.y }

	if t_near.x > t_far.y || t_near.y > t_far.x { c.hit = false;return }

	t_hit_near := max(t_near.x, t_near.y)
	t_hit_far := min(t_far.x, t_far.y)

	if t_hit_far < 0 { c.hit = false;return }

	// reject if collision happened in the past
	if t_hit_near < 0 { c.hit = false;return }

	// i think we can stop here?
	if t_hit_near > 1 { c.hit = false;return }

	c.point = origin + t_hit_near * ray_dir
	c.t = t_hit_near

	// calculate normal first
	if abs(t_near.x - t_near.y) < 0.001 {
		// choose the normal that points away from the approach direction
		if ray_dir.x < 0 &&
		   ray_dir.y <
			   0 { c.normal = {1, 1} } else if ray_dir.x > 0 && ray_dir.y < 0 { c.normal = {-1, 1} } else if ray_dir.x < 0 && ray_dir.y > 0 { c.normal = {1, -1} } else { c.normal = {-1, -1} }
		c.normal = lin.normalize(c.normal)
	} else if t_near.x > t_near.y {
		if ray_dir.x < 0 { c.normal = {1, 0} } else { c.normal = {-1, 0} }
	} else if t_near.x < t_near.y {
		if ray_dir.y < 0 { c.normal = {0, 1} } else { c.normal = {0, -1} }
	}

	// for t=0 collisions, prioritize based on how perpendicular the normal is to movement
	// more perpendicular = better for sliding = higher priority (lower sort value)
	if abs(c.t) < 0.001 {
		// calculate how parallel the normal is to movement direction
		ray_normalized := lin.normalize(ray_dir)
		dot_product := abs(lin.dot(c.normal, ray_normalized))

		// more perpendicular collisions get higher priority (smaller sort_t)
		c.sort_t = dot_product
	} else {
		c.sort_t = c.t
	}

	c.hit = true
	return
}

body_vs_body :: proc(d_body, s_body: ^Body, velocity: rl.Vector2, dt: f64) -> (c: Collision_Info) {
	// if velocity.x == 0 && velocity.y == 0 {c.hit = false;return}

	d_rect := body_to_rect(d_body^)
	s_rect := body_to_rect(s_body^)

	origin := rl.Vector2{d_rect.x + d_rect.width / 2, d_rect.y + d_rect.height / 2}
	expanded_target := rl.Rectangle {
		s_rect.x - d_rect.width / 2,
		s_rect.y - d_rect.height / 2,
		s_rect.width + d_rect.width,
		s_rect.height + d_rect.height,
	}

	// fmt.printfln("Expanded target: (%v, %v, %v, %v)", expanded_target.x, expanded_target.y, expanded_target.width, expanded_target.height)
	c = ray_vs_rect(origin, velocity * f32(dt), expanded_target)
	c.hit = c.hit && c.t >= 0 && c.t < 1
	c.body = s_body
	return
}
