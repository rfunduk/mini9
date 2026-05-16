package engine

import "core:log"
import b2 "lib:box2d"
import mrb "lib:mruby"
import rl "lib:raylib"

// ─── types ───

PHYSICS_SUB_STEPS :: 4
MAX_COLLISION_PLANES :: 16

@(private = "file")
physics_world: b2.WorldId

// Static + kinematic bodies whose position is driven by user code. Pre-step
// sync pushes each obj.pos back to box2d so that mutations like
// `this.pos.y -= n` (which bypass the pos= setter) still take effect. Dynamic
// bodies are excluded — their positions come FROM box2d via sync_dynamic_bodies.
@(private = "file")
user_driven_bodies: [dynamic]^Game_Object

track_user_driven_body :: proc(obj: ^Game_Object) {
	append(&user_driven_bodies, obj)
}

untrack_user_driven_body :: proc(obj: ^Game_Object) {
	for b, i in user_driven_bodies {
		if b == obj {
			unordered_remove(&user_driven_bodies, i)
			return
		}
	}
}

physics_body_count :: proc() -> int {
	return dynamic_body_count + len(user_driven_bodies)
}

physics_body_counts :: proc() -> (total, dynamic_n, user_driven_n: int) {
	return dynamic_body_count + len(user_driven_bodies), dynamic_body_count, len(user_driven_bodies)
}

// Deferred body destruction — user calls destroy_body mid-step, body is
// disabled immediately (no new physics interactions), then fully destroyed
// at end of the current step. Keeps shape/body ids valid for lookup through
// the rest of drain_sensor_events so handlers still receive valid `other`.
@(private = "file")
pending_destroy_bodies: [dynamic]^Game_Object

queue_destroy_body :: proc(obj: ^Game_Object) {
	if obj == nil || obj.destroy_queued { return }
	if !b2.Body_IsValid(obj.body_id) { return }
	obj.destroy_queued = true
	b2.Body_Disable(obj.body_id)
	append(&pending_destroy_bodies, obj)
}

// Remove obj from the pending-destroy list — called by the mruby finalizer
// if the obj is GC'd before the end-of-step flush runs, so the list doesn't
// carry a dangling pointer into the next flush.
unqueue_destroy_body :: proc(obj: ^Game_Object) {
	for p, i in pending_destroy_bodies {
		if p == obj {
			unordered_remove(&pending_destroy_bodies, i)
			return
		}
	}
}

flush_destroyed_bodies :: proc() {
	for obj in pending_destroy_bodies {
		if !b2.Body_IsValid(obj.body_id) { continue }
		if obj.body_type == .STATIC || obj.body_type == .KINEMATIC {
			untrack_user_driven_body(obj)
		}
		b2.DestroyBody(obj.body_id)
		if obj.body_type == .DYNAMIC { dynamic_body_count -= 1 }
		obj.body_id = {}
		obj.destroy_queued = false
	}
	clear(&pending_destroy_bodies)
}

sync_user_driven_positions :: proc() {
	for obj in user_driven_bodies {
		if !b2.Body_IsValid(obj.body_id) { continue }
		v := extract_native(rl.Vector2, obj.pos)
		if v == nil { continue }
		new_center := v^ + obj.body_center_offset
		if new_center == obj.last_sync_center && obj.rotation == obj.last_sync_rotation { continue }
		b2.Body_SetTransform(obj.body_id, new_center, b2.MakeRot(obj.rotation))
		obj.last_sync_center = new_center
		obj.last_sync_rotation = obj.rotation
	}
}

// Exposed to sibling engine_* files that need to query the world (e.g. navmesh
// obstacle extraction). Keeps the underlying id file-private otherwise.
physics_world_id :: proc() -> b2.WorldId { return physics_world }

// shared with engine_game_object (body create/destroy bumps this)
dynamic_body_count: int

Body_Type :: enum {
	NONE,
	STATIC,
	KINEMATIC,
	DYNAMIC,
}

Physics_Shape_Kind :: enum {
	NONE,
	BOX,
	CIRCLE,
}

// ─── layer helpers ───

// Convert a Ruby layer spec to a bitmask.
// Single integer N -> bit (N-1), i.e. layer 1 = 0x0001, layer 3 = 0x0004
// Array [1, 3] -> 0x0001 | 0x0004
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

step_physics :: proc() {
	if !b2.World_IsValid(physics_world) { return }

	// Push any user-driven body positions to box2d before stepping — catches
	// in-place pos mutations (e.g. `this.pos.y -= n`) that bypass pos=.
	sync_user_driven_positions()

	// Always step if any sensor could have overlaps to track; otherwise skip
	// when no dynamic bodies (static/kinematic don't need simulation).
	if dynamic_body_count == 0 {
		// Still need a step so sensor overlap begin/end events fire when
		// kinematic-driven (position-set) bodies move into sensors.
		b2.World_Step(physics_world, FIXED_DT, PHYSICS_SUB_STEPS)
		drain_sensor_events()
		flush_destroyed_bodies()
		return
	}

	b2.World_Step(physics_world, FIXED_DT, PHYSICS_SUB_STEPS)
	drain_sensor_events()
	sync_dynamic_bodies()
	flush_destroyed_bodies()
}

// Drain box2d sensor events. Each event reports one sensor + one visitor.
// Dispatch rules:
//   - Always notify the sensor side.
//   - If the visitor is a non-sensor, notify it too — this is the only event
//     box2d generates for that pair.
//   - If the visitor is also a sensor, skip it here; box2d emits a mirror
//     event with roles swapped, and that event will cover the visitor side.
//
// Net result: every obj involved in a sensor interaction receives exactly
// one on_enter/on_exit, regardless of sensor/non-sensor mix.
drain_sensor_events :: proc() {
	events := b2.World_GetSensorEvents(physics_world)

	for i in 0 ..< events.beginCount {
		e := events.beginEvents[i]
		sensor_val := obj_value_from_shape(e.sensorShapeId)
		visitor_val := obj_value_from_shape(e.visitorShapeId)
		if sensor_val != mrb.NIL { maybe_dispatch(sensor_val, "on_enter", visitor_val) }
		if visitor_val != mrb.NIL && !b2.Shape_IsSensor(e.visitorShapeId) {
			maybe_dispatch(visitor_val, "on_enter", sensor_val)
		}
	}

	for i in 0 ..< events.endCount {
		e := events.endEvents[i]
		sensor_val := obj_value_from_shape(e.sensorShapeId)
		visitor_val := obj_value_from_shape(e.visitorShapeId)
		if sensor_val != mrb.NIL { maybe_dispatch(sensor_val, "on_exit", visitor_val) }
		if visitor_val != mrb.NIL &&
		   b2.Shape_IsValid(e.visitorShapeId) &&
		   !b2.Shape_IsSensor(e.visitorShapeId) {
			maybe_dispatch(visitor_val, "on_exit", sensor_val)
		}
	}
}

@(private = "file")
obj_value_from_shape :: proc(shape_id: b2.ShapeId) -> mrb.Value {
	if !b2.Shape_IsValid(shape_id) { return mrb.NIL }
	body := b2.Shape_GetBody(shape_id)
	if !b2.Body_IsValid(body) { return mrb.NIL }
	ud := b2.Body_GetUserData(body)
	if ud == nil { return mrb.NIL }
	obj := cast(^Game_Object)ud
	return obj.self_val
}

@(private = "file")
maybe_dispatch :: proc(receiver: mrb.Value, method: cstring, arg: mrb.Value) {
	if !mrb.respond_to(g.mrb_state, receiver, mrb.intern_cstr(g.mrb_state, method)) { return }
	argv: [1]mrb.Value = {arg}
	dispatch_funcall(receiver, method, 1, raw_data(argv[:]), .SENSOR_EVENT)
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
		top_left := pos - obj.body_center_offset

		// Mutate obj.pos in place to avoid per-step allocation (each dynamic
		// body would otherwise churn ~1 Vector2 per physics step, saturating
		// the old-gen and triggering frequent major GC cycles).
		if obj.pos != mrb.NIL {
			v := extract_native(rl.Vector2, obj.pos)
			if v != nil { v^ = top_left }
		} else {
			obj.pos = create_vector2(top_left)
			mrb.gc_register(g.mrb_state, obj.pos)
		}
		obj.last_sync_center = pos

		if obj.spin {
			obj.rotation = b2.Rot_GetAngle(b2.Body_GetRotation(event.bodyId))
			obj.last_sync_rotation = obj.rotation
		}
	}
}

// ─── body creation (called from ruby_obj) ───

create_physics_body :: proc(
	body_type: Body_Type,
	pos: rl.Vector2,
	rotation: f32,
	shape_kind: Physics_Shape_Kind,
	half_size: rl.Vector2,
	radius: f32,
	center_offset: rl.Vector2,
	layer, mask: u64,
	density, friction, restitution, drag, ang_drag: f32,
	sensor: bool,
	spin: bool,
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
	body_def.fixedRotation = !spin
	body_def.enableSleep = false
	body_def.linearDamping = drag
	body_def.angularDamping = ang_drag
	// body center = pos + shape's center-offset
	body_def.position = {pos.x + center_offset.x, pos.y + center_offset.y}
	body_def.rotation = b2.MakeRot(rotation)

	body_id := b2.CreateBody(physics_world, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = density
	shape_def.material.friction = friction
	shape_def.material.restitution = restitution
	shape_def.isSensor = sensor
	shape_def.enableContactEvents = true
	// Needed on BOTH sides of a sensor interaction — non-sensors must have
	// it enabled to be detectable as visitors. Default-on everywhere.
	shape_def.enableSensorEvents = true

	// Shape filter: explicit-only. No mask -> interacts with nothing. Forces
	// users to opt-in to collisions/overlaps via layer+mask pair.
	//
	// Box2d contact rule: (a.cat & b.mask) && (b.cat & a.mask). Mover API's
	// own QueryFilter is evaluated on top of this, unaffected.
	shape_def.filter.categoryBits = layer
	shape_def.filter.maskBits = mask

	shape_id: b2.ShapeId
	switch shape_kind {
	case .BOX:
		box := b2.MakeBox(half_size.x, half_size.y)
		shape_id = b2.CreatePolygonShape(body_id, shape_def, box)
	case .CIRCLE:
		circle := b2.Circle {
			center = {0, 0},
			radius = radius,
		}
		shape_id = b2.CreateCircleShape(body_id, shape_def, circle)
	case .NONE: // unreachable — validated upstream
	}

	return body_id, shape_id
}

// Describe the current collider so a flag-only swap (sensor=) can rebuild the
// same geometry. half_size/center_offset are mirrored on the Game_Object;
// radius must be read back from box2d (not stored).
shape_descriptor :: proc(
	obj: ^Game_Object,
) -> (
	kind: Physics_Shape_Kind,
	half: rl.Vector2,
	radius: f32,
	offset: rl.Vector2,
) {
	half = obj.half_size
	offset = obj.body_center_offset
	#partial switch b2.Shape_GetType(obj.shape_id) {
	case .circleShape:
		kind = .CIRCLE
		radius = b2.Shape_GetCircle(obj.shape_id).radius
	case:
		kind = .BOX
	}
	return
}

// Swap the collider on a live body in place. body_id is preserved, so
// velocity, transform and joints survive — only the b2.Shape is destroyed and
// recreated. Material (density/friction/restitution/filter) is read off the
// old shape BEFORE destruction and reapplied, so a shape= swap doesn't
// silently reset physics material (those props live only in box2d, not on the
// Game_Object). isSensor is creation-time-immutable in box2d v3
// (Shape_EnableSensorEvents only toggles event reporting, not isSensor), so
// sensor= must route here too. Legal only outside World_Step
rebuild_body_shape :: proc(
	obj: ^Game_Object,
	new_kind: Physics_Shape_Kind,
	new_half_size: rl.Vector2,
	new_radius: f32,
	new_center_offset: rl.Vector2,
	new_sensor: bool,
) {
	old := obj.shape_id
	density := b2.Shape_GetDensity(old)
	friction := b2.Shape_GetFriction(old)
	restitution := b2.Shape_GetRestitution(old)
	filter := b2.Shape_GetFilter(old)

	b2.DestroyShape(old, false)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = density
	shape_def.material.friction = friction
	shape_def.material.restitution = restitution
	shape_def.isSensor = new_sensor
	shape_def.enableContactEvents = true
	shape_def.enableSensorEvents = true
	shape_def.filter = filter

	switch new_kind {
	case .BOX:
		box := b2.MakeBox(new_half_size.x, new_half_size.y)
		obj.shape_id = b2.CreatePolygonShape(obj.body_id, shape_def, box)
	case .CIRCLE:
		circle := b2.Circle {
			center = {0, 0},
			radius = new_radius,
		}
		obj.shape_id = b2.CreateCircleShape(obj.body_id, shape_def, circle)
	case .NONE: // unreachable — validated by caller
	}

	obj.half_size = new_half_size
	obj.body_center_offset = new_center_offset
	obj.sensor = new_sensor
	b2.Body_ApplyMassFromShapes(obj.body_id)

	// Keep the obj visually anchored if the center offset changed: re-pin the
	// body center to pos + new offset (matches sync_user_driven_positions).
	if v := extract_native(rl.Vector2, obj.pos); v != nil {
		new_center := v^ + new_center_offset
		b2.Body_SetTransform(obj.body_id, new_center, b2.MakeRot(obj.rotation))
		obj.last_sync_center = new_center
		obj.last_sync_rotation = obj.rotation
	}
}

// ─── mover API ───

physics_move :: proc(obj: ^Game_Object, vel: rl.Vector2, dt: f32) -> rl.Vector2 {
	translation := vel * dt

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
	fraction := b2.World_CastMover(physics_world, mover, translation, query_filter)

	// move to safe position
	safe_t := translation * fraction
	new_center := pos + safe_t

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
		remaining := translation - safe_t
		solve_result := b2.SolvePlanes(remaining, active_planes)
		new_center += solve_result.translation
	}

	// update box2d body position
	b2.Body_SetTransform(obj.body_id, new_center, b2.MakeRot(obj.rotation))
	obj.last_sync_center = new_center
	obj.last_sync_rotation = obj.rotation

	// sync back to game object pos — round to nearest pixel to avoid
	// sub-pixel drift from box2d float math (285.999 -> 286 not 285)
	biased := new_center - obj.body_center_offset + 0.5
	top_left := rl.Vector2{f32(int(biased.x)), f32(int(biased.y))}

	// Mutate in place to avoid per-call allocation — same rationale as
	// sync_dynamic_bodies above.
	if obj.pos != mrb.NIL {
		v := extract_native(rl.Vector2, obj.pos)
		if v != nil { v^ = top_left }
	} else {
		obj.pos = create_vector2(top_left)
		mrb.gc_register(g.mrb_state, obj.pos)
	}

	// clip velocity for next frame
	if plane_count > 0 {
		clipped := b2.ClipVector({vel.x, vel.y}, active_planes)
		return {clipped.x, clipped.y}
	}
	return vel
}

// ─── gravity ───

// RUBY FUNCTION: gravity(v2) -> sets world gravity
// @engine_method: name="gravity", aspec=ARGS_REQ(1)
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

@(private = "file")
Cast_Ctx :: struct {
	results: mrb.Value,
	limit:   i32, // -1 = unlimited
	count:   i32,
}

@(private = "file")
build_hit :: proc(shape_id: b2.ShapeId, point, normal: b2.Vec2, fraction: f32) -> mrb.Value {
	s := g.mrb_state
	hit_class := mrb.class_get(s, "Hit")
	pt := create_vector2({point.x, point.y})
	nm := create_vector2({normal.x, normal.y})
	fr := mrb.word_boxing_float_value(s, f64(fraction))
	coll := obj_value_from_shape(shape_id)
	args := [4]mrb.Value{pt, nm, fr, coll}
	return mrb.obj_new(s, hit_class, 4, raw_data(args[:]))
}

@(private = "file")
raycast_callback :: proc "c" (
	shape_id: b2.ShapeId,
	point, normal: b2.Vec2,
	fraction: f32,
	raw_ctx: rawptr,
) -> f32 {
	context = global_context
	c := cast(^Cast_Ctx)raw_ctx
	hit := build_hit(shape_id, point, normal, fraction)
	mrb.ary_push(g.mrb_state, c.results, hit)
	c.count += 1
	if c.limit > 0 && c.count >= c.limit { return 0 } 	// terminate
	return -1 // skip + continue (collect all hits)
}

// RUBY FUNCTION: raycast(origin:, direction:, mask: ALL, limit: 1, shape: nil) -> [Hit, ...]
// @engine_method: name="raycast", aspec=ARGS_OPT(1)
ruby_raycast :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)
	if kwargs == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "raycast requires keyword arguments")
	}

	origin_val := mrb.kwarg(state, kwargs, sym.origin)
	if origin_val == mrb.NIL { origin_val = create_vector2({}) }
	origin := extract_native(rl.Vector2, origin_val)
	if origin == nil {
		return mrb.raise_error(state, "TypeError", "raycast: `origin:` must be a Vector2")
	}

	dir_val := mrb.kwarg(state, kwargs, sym.direction)
	if dir_val == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "raycast: missing `direction:`")
	}
	dir := extract_native(rl.Vector2, dir_val)
	if dir == nil {
		return mrb.raise_error(state, "TypeError", "raycast: `direction:` must be a Vector2")
	}

	mask: u64 = 0xFFFFFFFFFFFFFFFF
	if v := mrb.kwarg(state, kwargs, sym.mask); v != mrb.NIL {
		mask = layer_to_bitmask(state, v)
	}

	limit: i32 = 1
	if v := mrb.kwarg(state, kwargs, sym.limit); v != mrb.NIL {
		if !mrb.integer_p(v) {
			return mrb.raise_error(state, "TypeError", "raycast: `limit:` must be an Integer")
		}
		limit = i32(mrb.integer(v))
	}

	filter := b2.DefaultQueryFilter()
	filter.categoryBits = 0xFFFFFFFFFFFFFFFF
	filter.maskBits = mask

	// Validate `shape:` (if any) BEFORE allocating the results array — keeps
	// error paths free of GC roots that would need cleanup. raise_error uses
	// longjmp and skips deferred unregister.
	shape_val := mrb.kwarg(state, kwargs, sym.shape)
	if shape_val != mrb.NIL && !is_native(Circ, shape_val) && !is_native(rl.Rectangle, shape_val) {
		return mrb.raise_error(state, "TypeError", "raycast: `shape:` must be nil, Circ, or Rect")
	}

	results := mrb.ary_new(g.mrb_state)

	// limit == 0 short-circuits — no work, empty result
	if limit == 0 { return results }

	mrb.gc_register(state, results)
	defer mrb.gc_unregister(state, results)

	ctx := Cast_Ctx {
		results = results,
		limit   = limit,
		count   = 0,
	}

	if shape_val == mrb.NIL {
		_ = b2.World_CastRay(physics_world, origin^, dir^, filter, raycast_callback, &ctx)
	} else if is_native(Circ, shape_val) {
		c := extract_native(Circ, shape_val)
		if c.center.x != 0 || c.center.y != 0 {
			log.warnf(
				"raycast: Circ shape position (%v, %v) ignored — cast happens at `origin:`",
				c.center.x,
				c.center.y,
			)
		}
		pts := [1]b2.Vec2{origin^}
		proxy := b2.MakeProxy(pts[:], c.r)
		_ = b2.World_CastShape(physics_world, proxy, dir^, filter, raycast_callback, &ctx)
	} else {
		// rl.Rectangle (validated above)
		r := extract_native(rl.Rectangle, shape_val)
		if r.x != 0 || r.y != 0 {
			log.warnf(
				"raycast: Rect shape position (%v, %v) ignored — cast happens at `origin:`",
				r.x,
				r.y,
			)
		}
		hw := r.width / 2
		hh := r.height / 2
		cx := origin^.x
		cy := origin^.y
		pts := [4]b2.Vec2{{cx - hw, cy - hh}, {cx + hw, cy - hh}, {cx + hw, cy + hh}, {cx - hw, cy + hh}}
		proxy := b2.MakeProxy(pts[:], 0)
		_ = b2.World_CastShape(physics_world, proxy, dir^, filter, raycast_callback, &ctx)
	}

	return results
}

cleanup_physics :: proc() {
	if b2.World_IsValid(physics_world) { b2.DestroyWorld(physics_world) }
	delete(user_driven_bodies)
	user_driven_bodies = nil
	delete(pending_destroy_bodies)
	pending_destroy_bodies = nil
}
