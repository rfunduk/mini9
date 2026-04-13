package engine

import mrb "lib:mruby"
import b2 "lib:box2d"
import rl "vendor:raylib"

// ─── types ───

PHYSICS_SUB_STEPS :: 4
MAX_COLLISION_PLANES :: 16

@(private = "file")
physics_world: b2.WorldId

// shared with engine_game_object (body create/destroy bumps this)
dynamic_body_count: int

Body_Type :: enum {
	NONE,
	STATIC,
	KINEMATIC,
	DYNAMIC,
}

// ─── layer helpers ───

// Convert a Ruby layer spec to a bitmask.
// Single integer N → bit (N-1), i.e. layer 1 = 0x0001, layer 3 = 0x0004
// Array [1, 3] → 0x0001 | 0x0004
layer_to_bitmask :: proc(state: mrb.State, val: mrb.Value) -> u64 {
	if val == mrb.NIL { return 0 }

	if mrb.integer_p(val) {
		n := mrb.integer(val)
		if n < 1 || n > 64 { return 0 }
		return 1 << u64(n - 1)
	}

	if mrb.array_p(val) {
		mask: u64 = 0
		len := mrb.ary_len(val)
		for i in 0 ..< len {
			entry := mrb.ary_entry(val, i32(i))
			if mrb.integer_p(entry) {
				n := mrb.integer(entry)
				if n >= 1 && n <= 64 {
					mask |= 1 << u64(n - 1)
				}
			}
		}
		return mask
	}

	return 0
}

// ─── world management ───

setup_physics :: proc() {
	b2.SetLengthUnitsPerMeter(16)

	world_def := b2.DefaultWorldDef()
	world_def.gravity = {0, 0}
	world_def.enableSleep = false

	physics_world = b2.CreateWorld(world_def)
}

step_physics :: proc(dt: f32) {
	if !b2.World_IsValid(physics_world) { return }
	// only step if dynamic bodies exist — static/kinematic don't need simulation
	if dynamic_body_count == 0 { return }

	b2.World_Step(physics_world, dt, PHYSICS_SUB_STEPS)
	sync_dynamic_bodies()
}

// push box2d positions back to game objects for dynamic bodies
sync_dynamic_bodies :: proc() {
	events := b2.World_GetBodyEvents(physics_world)
	for i in 0 ..< events.moveCount {
		event := events.moveEvents[i]
		if !b2.Body_IsValid(event.bodyId) { continue }

		user_data := b2.Body_GetUserData(event.bodyId)
		if user_data == nil { continue }

		obj := cast(^Game_Object)user_data

		pos := b2.Body_GetPosition(event.bodyId)
		top_left := rl.Vector2{pos.x - obj.half_size.x, pos.y - obj.half_size.y}
		new_pos := create_vector2(top_left)

		if obj.pos != mrb.NIL { mrb.gc_unregister(g.mrb_state, obj.pos) }
		mrb.gc_register(g.mrb_state, new_pos)
		obj.pos = new_pos
	}
}

// ─── body creation (called from ruby_obj) ───

create_physics_body :: proc(
	body_type: Body_Type,
	pos: rl.Vector2,
	half_size: rl.Vector2,
	layer, mask: u64,
	density, friction, restitution: f32,
	sensor: bool,
) -> (
	b2.BodyId,
	b2.ShapeId,
) {
	body_def := b2.DefaultBodyDef()
	switch body_type {
	case .STATIC:
		body_def.type = .staticBody
	case .KINEMATIC:
		body_def.type = .kinematicBody
	case .DYNAMIC:
		body_def.type = .dynamicBody
	case .NONE: // unreachable
	}
	body_def.fixedRotation = true
	body_def.enableSleep = false
	// set position at creation — center of the box
	body_def.position = {pos.x + half_size.x, pos.y + half_size.y}

	body_id := b2.CreateBody(physics_world, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = density
	shape_def.material.friction = friction
	shape_def.material.restitution = restitution
	shape_def.isSensor = sensor
	shape_def.enableContactEvents = true
	shape_def.enableSensorEvents = sensor

	// Godot-style filtering: shape always accepts queries.
	// Actual filtering done by the mover's QueryFilter.
	shape_def.filter.categoryBits = layer
	shape_def.filter.maskBits = 0xFFFFFFFFFFFFFFFF

	box := b2.MakeBox(half_size.x, half_size.y)
	shape_id := b2.CreatePolygonShape(body_id, shape_def, box)

	return body_id, shape_id
}

// ─── mover API ───

physics_move :: proc(obj: ^Game_Object, vel: rl.Vector2, dt: f32) -> rl.Vector2 {
	translation := rl.Vector2{vel.x * dt, vel.y * dt}

	pos := b2.Body_GetPosition(obj.body_id)

	// build capsule to approximate box — shorter axis as radius,
	// longer axis extends the capsule line
	cap_radius := min(obj.half_size.x, obj.half_size.y)
	cap_extent := max(obj.half_size.x, obj.half_size.y) - cap_radius
	vertical := obj.half_size.y >= obj.half_size.x

	mover: b2.Capsule
	if vertical {
		mover = {
			center1 = {pos.x, pos.y - cap_extent},
			center2 = {pos.x, pos.y + cap_extent},
			radius  = cap_radius,
		}
	} else {
		mover = {
			center1 = {pos.x - cap_extent, pos.y},
			center2 = {pos.x + cap_extent, pos.y},
			radius  = cap_radius,
		}
	}

	query_filter := b2.DefaultQueryFilter()
	query_filter.categoryBits = obj.layer
	query_filter.maskBits = obj.mask

	// cast mover to find safe travel fraction
	fraction := b2.World_CastMover(physics_world, mover, {translation.x, translation.y}, query_filter)

	// move to safe position
	safe_t := b2.Vec2{translation.x * fraction, translation.y * fraction}
	new_center := b2.Vec2{pos.x + safe_t.x, pos.y + safe_t.y}

	// update capsule for collision query
	if vertical {
		mover.center1 = {new_center.x, new_center.y - cap_extent}
		mover.center2 = {new_center.x, new_center.y + cap_extent}
	} else {
		mover.center1 = {new_center.x - cap_extent, new_center.y}
		mover.center2 = {new_center.x + cap_extent, new_center.y}
	}

	// gather collision planes for sliding
	planes: [MAX_COLLISION_PLANES]b2.CollisionPlane
	plane_count: i32 = 0

	Plane_Ctx :: struct {
		planes: ^[MAX_COLLISION_PLANES]b2.CollisionPlane,
		count:  ^i32,
	}
	ctx := Plane_Ctx{&planes, &plane_count}

	b2.World_CollideMover(
		physics_world,
		mover,
		query_filter,
		proc "c" (shape_id: b2.ShapeId, result: ^b2.PlaneResult, raw_ctx: rawptr) -> bool {
			c := cast(^Plane_Ctx)raw_ctx
			if !result.hit { return true }
			if c.count^ >= MAX_COLLISION_PLANES { return false }
			c.planes[c.count^] = b2.CollisionPlane {
				plane        = result.plane,
				pushLimit    = max(f32),
				clipVelocity = true,
			}
			c.count^ += 1
			return true
		},
		&ctx,
	)

	active_planes := planes[:plane_count]

	// solve planes for position correction
	if plane_count > 0 {
		remaining := b2.Vec2{translation.x - safe_t.x, translation.y - safe_t.y}
		solve_result := b2.SolvePlanes(remaining, active_planes)
		new_center.x += solve_result.translation.x
		new_center.y += solve_result.translation.y
	}

	// update box2d body position
	b2.Body_SetTransform(obj.body_id, new_center, b2.Rot_identity)

	// sync back to game object pos — round to nearest pixel to avoid
	// sub-pixel drift from box2d float math (285.999 → 286 not 285)
	top_left := rl.Vector2 {
		f32(int(new_center.x - obj.half_size.x + 0.5)),
		f32(int(new_center.y - obj.half_size.y + 0.5)),
	}
	new_pos := create_vector2(top_left)
	if obj.pos != mrb.NIL { mrb.gc_unregister(g.mrb_state, obj.pos) }
	mrb.gc_register(g.mrb_state, new_pos)
	obj.pos = new_pos

	// clip velocity for next frame
	if plane_count > 0 {
		clipped := b2.ClipVector({vel.x, vel.y}, active_planes)
		return {clipped.x, clipped.y}
	}
	return vel
}

// ─── gravity ───

// RUBY FUNCTION: gravity(v2) -> sets world gravity
// @engine_method: name="gravity", arity=1
ruby_gravity :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	gravity_val: mrb.Value
	mrb.get_args(state, "o", &gravity_val)

	grav := extract_native(rl.Vector2, gravity_val)
	if grav != nil {
		b2.World_SetGravity(physics_world, {grav.x, grav.y})
	} else if mrb.float_p(gravity_val) || mrb.integer_p(gravity_val) {
		b2.World_SetGravity(physics_world, {0, f32(mrb.to_f64(gravity_val))})
	} else {
		return mrb.raise_error(state, "ArgumentError", "gravity expects a Vector2 or number")
	}

	return mrb.NIL
}

// ─── raycast ───

// RUBY FUNCTION: raycast(origin, direction, mask) -> [hit, point, normal, fraction]
// @engine_method: name="raycast", arity=3
ruby_raycast :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	origin_val, dir_val, mask_val: mrb.Value
	mrb.get_args(state, "ooo", &origin_val, &dir_val, &mask_val)

	origin := extract_native(rl.Vector2, origin_val)
	dir := extract_native(rl.Vector2, dir_val)
	if origin == nil || dir == nil { return mrb.NIL }

	query_filter := b2.DefaultQueryFilter()
	query_filter.maskBits = u64(mrb.integer(mask_val))
	query_filter.categoryBits = 0xFFFFFFFFFFFFFFFF

	result := b2.World_CastRayClosest(physics_world, {origin.x, origin.y}, {dir.x, dir.y}, query_filter)

	result_array := mrb.ary_new(g.mrb_state)
	mrb.ary_push(g.mrb_state, result_array, result.hit ? mrb.TRUE : mrb.FALSE)
	mrb.ary_push(
		g.mrb_state,
		result_array,
		result.hit ? create_vector2({result.point.x, result.point.y}) : mrb.NIL,
	)
	mrb.ary_push(
		g.mrb_state,
		result_array,
		result.hit ? create_vector2({result.normal.x, result.normal.y}) : mrb.NIL,
	)
	mrb.ary_push(g.mrb_state, result_array, mrb.word_boxing_float_value(state, f64(result.fraction)))

	return result_array
}

cleanup_physics :: proc() {
	if b2.World_IsValid(physics_world) {
		b2.DestroyWorld(physics_world)
	}
}
