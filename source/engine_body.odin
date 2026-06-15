package engine

import b2 "lib:box2d"
import mrb "lib:mruby"
import rl "lib:raylib"

// Spec produced by `body()` and consumed by `obj(body: ...)`. Short-lived: it
// only exists between the body() call and obj() construction. Not user-facing
// past that — has no methods.
Body_Spec :: struct {
	body_type:          Body_Type,
	shape_kind:         Physics_Shape_Kind,
	shape_val:          mrb.Value,
	half_size:          rl.Vector2,
	radius:             f32,
	body_center_offset: rl.Vector2,
	layer, mask:        u64,
	density:            f32,
	friction:           f32,
	restitution:        f32,
	drag:               f32,
	ang_drag:           f32,
	sensor:             bool,
	spin:               bool,
}

// shape_val is kept alive by a temporary gc_register BRIDGE installed in
// body() (see there), handed off to the Body wrapper's @__shape ivar in
// ruby_obj, which then drops the bridge. A body() that is never consumed by
// obj() leaks its shape's bridge root — acceptable: body() is only valid as
// the `body:` kwarg of obj(), which always consumes it.
ruby_bodyspec_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

// Body wrapper: thin shell pointing back at the parent Game_Object. All
// physics state still lives in the Game_Object; this is just the ruby
// surface for body methods. Finalized with the parent.
Body :: struct {
	obj: ^Game_Object,
}

ruby_body_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_body_wrapper :: proc(obj: ^Game_Object) -> mrb.Value {
	b := Body {
		obj = obj,
	}
	ptr := mrb.alloc(g.mrb_state, b)
	class := mrb.class_get(g.mrb_state, "Body")
	val := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(val, ptr, NATIVE_TO_MRUBY_TYPE[Body])
	return val
}

@(private = "file")
body_obj :: proc(self: mrb.Value) -> ^Game_Object {
	b := extract_native(Body, self)
	if b == nil { return nil }
	return b.obj
}

// RUBY FUNCTION: body(type, shape:, layer:, mask:, sensor:, density:, friction:, restitution:, drag:, ang_drag:, spin:)
// @engine_method: name="body", aspec=ARGS_ARG(1,1)
ruby_body :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	type_val: mrb.Value
	kwargs: mrb.Value
	mrb.get_args(state, "o|H", &type_val, &kwargs)

	if !mrb.symbol_p(type_val) {
		return mrb.raise_error(
			state,
			"ArgumentError",
			"body: first arg must be :static, :kinematic, or :dynamic",
		)
	}

	body_type := Body_Type.NONE
	switch mrb.to_string(state, type_val) {
	case "static":
		body_type = .STATIC
	case "kinematic":
		body_type = .KINEMATIC
	case "dynamic":
		body_type = .DYNAMIC
	case:
		return mrb.raise_error(state, "ArgumentError", "body: type must be :static, :kinematic, or :dynamic")
	}

	spec := Body_Spec {
		body_type   = body_type,
		shape_val   = mrb.NIL,
		density     = 1.0,
		friction    = 0.3,
		restitution = 0.0,
	}

	mask_provided := false

	if kwargs != mrb.NIL {
		val: mrb.Value

		val = mrb.kwarg(state, kwargs, sym.shape)
		if val != mrb.NIL {
			if c := extract_or_nil(Circ, val); c != nil {
				spec.shape_kind = .CIRCLE
				spec.radius = c.r
				spec.half_size = {c.r, c.r}
				spec.body_center_offset = c.center
			} else if r := extract_or_nil(rl.Rectangle, val); r != nil {
				spec.shape_kind = .BOX
				spec.half_size = {r.width / 2, r.height / 2}
				spec.body_center_offset = {r.x + r.width / 2, r.y + r.height / 2}
			} else {
				return mrb.raise_error(state, "TypeError", "body: shape: must be a Circ or Rect")
			}
			spec.shape_val = val
		}

		val = mrb.kwarg(state, kwargs, sym.layer)
		if val != mrb.NIL { spec.layer = layer_to_bitmask(state, val) }
		val = mrb.kwarg(state, kwargs, sym.mask)
		if val != mrb.NIL {
			spec.mask = layer_to_bitmask(state, val)
			mask_provided = true
		}
		val = mrb.kwarg(state, kwargs, sym.sensor)
		if val != mrb.NIL { spec.sensor = mrb.boolean(val) }
		val = mrb.kwarg(state, kwargs, sym.density)
		if val != mrb.NIL { spec.density = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, sym.friction)
		if val != mrb.NIL { spec.friction = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, sym.restitution)
		if val != mrb.NIL { spec.restitution = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, sym.drag)
		if val != mrb.NIL { spec.drag = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, sym.ang_drag)
		if val != mrb.NIL { spec.ang_drag = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, sym.spin)
		if val != mrb.NIL { spec.spin = mrb.boolean(val) }
	}

	if spec.shape_kind == .NONE {
		return mrb.raise_error(state, "ArgumentError", "body: shape: is required (Circ or Rect)")
	}
	if spec.spin && body_type != .DYNAMIC {
		return mrb.raise_error(state, "ArgumentError", "body: spin: true requires :dynamic")
	}

	// non-sensor default mask = "see everything"; sensor stays 0 (opt-in)
	if !spec.sensor && !mask_provided { spec.mask = 0xFFFFFFFFFFFFFFFF }

	ptr := mrb.alloc(g.mrb_state, spec)
	class := mrb.class_get(g.mrb_state, "BodySpec")
	val := mrb.obj_new(g.mrb_state, class, 0, nil)
	mrb.data_init(val, ptr, NATIVE_TO_MRUBY_TYPE[Body_Spec])
	// ┌─ FRAGILE: shape lifetime BRIDGE — half 1 of 2 ──────────────────────┐
	// │ Pairs with the gc_unregister in ruby_obj (engine_game_object.odin). │
	// │ Do not remove one half without the other.                           │
	// └─────────────────────────────────────────────────────────────────────┘
	// Why a gc_register and not just the @__shape ivar: the BodySpec is
	// short-lived. mruby restores the GC arena after this C builtin returns,
	// and ruby_obj deletes the `body:` kwarg (hash_delete_key) BEFORE it
	// builds the lasting obj<->body->shape chain. In that window the BodySpec
	// — and any @__shape ivar hung on it — is unreachable and can be swept,
	// taking the only shape reference with it (observed: shape returned as a
	// recycled String). A gc_register root is independent of the BodySpec and
	// spans the gap. ruby_obj drops it once the durable chain exists.
	//
	// Invariant: every BodySpec that reaches ruby_obj MUST have its shape
	// unregistered there exactly once. body() is only valid as obj()'s `body:`
	// kwarg, so a BodySpec that is never consumed leaks this one root — an
	// accepted, bounded cost (one misuse = one leaked Circ/Rect).
	if spec.shape_val != mrb.NIL { mrb.gc_register(state, spec.shape_val) }
	return val
}

// ─── Body methods ───

// RUBY METHOD: body.type -> :static / :kinematic / :dynamic
ruby_body_type :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.NIL }
	switch obj.body_type {
	case .STATIC:
		return sym.static
	case .KINEMATIC:
		return sym.kinematic
	case .DYNAMIC:
		return sym.dynamic_
	case .NONE:
		return mrb.NIL
	}
	return mrb.NIL
}

// RUBY METHOD: body.shape -> Circ | Rect (the shape passed at construction)
ruby_body_shape :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.NIL }
	return obj.shape_val
}

// RUBY METHOD: body.sensor? -> bool
ruby_body_sensor :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.FALSE }
	return obj.sensor ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: body.layer -> Integer (1..64; 0 if unset). Single bit only.
ruby_body_layer :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.fixnum_value(0) }
	bm := obj.layer
	if bm == 0 { return mrb.fixnum_value(0) }
	for n in 1 ..= 64 {
		if bm & 1 != 0 { return mrb.fixnum_value(mrb.Int(n)) }
		bm >>= 1
	}
	return mrb.fixnum_value(0)
}

// RUBY METHOD: body.mask -> Integer (raw bitmask). Use bit ops for tests.
ruby_body_mask :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.fixnum_value(0) }
	return mrb.fixnum_value(mrb.Int(obj.mask))
}

// RUBY METHOD: body.spin? -> bool
ruby_body_spin :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.FALSE }
	return obj.spin ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: body.destroy -> nil  (queues body destruction at end of step)
ruby_body_destroy :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil { return mrb.NIL }
	queue_destroy_body(obj)
	return mrb.NIL
}

// RUBY METHOD: body.move(velocity) -> clipped velocity (mover API)
ruby_body_move :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	vel_val: mrb.Value
	mrb.get_args(state, "o", &vel_val)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return create_vector2({0, 0}) }
	vel := extract_native(rl.Vector2, vel_val)
	if vel == nil { return create_vector2({0, 0}) }
	clipped := physics_move(obj, vel^, FIXED_DT)
	return create_vector2(clipped)
}

// RUBY METHOD: body.apply_force(v2) -> self
ruby_body_apply_force :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return self }
	f := extract_native(rl.Vector2, v)
	if f == nil { return self }
	b2.Body_ApplyForceToCenter(obj.body_id, {f.x, f.y}, true)
	return self
}

// RUBY METHOD: body.apply_impulse(v2) -> self
ruby_body_apply_impulse :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return self }
	i := extract_native(rl.Vector2, v)
	if i == nil { return self }
	b2.Body_ApplyLinearImpulseToCenter(obj.body_id, {i.x, i.y}, true)
	return self
}

// RUBY METHOD: body.apply_torque(t) -> self
ruby_body_apply_torque :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	t: f64
	mrb.get_args(state, "f", &t)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return self }
	b2.Body_ApplyTorque(obj.body_id, f32(t), true)
	return self
}

// RUBY METHOD: body.linear_vel -> Vector2
ruby_body_linear_vel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return create_vector2({0, 0}) }
	v := b2.Body_GetLinearVelocity(obj.body_id)
	return create_vector2({v.x, v.y})
}

// RUBY METHOD: body.linear_vel = v2
ruby_body_set_linear_vel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return mrb.NIL }
	vec := extract_native(rl.Vector2, v)
	if vec == nil { return mrb.NIL }
	b2.Body_SetLinearVelocity(obj.body_id, {vec.x, vec.y})
	return v
}

// RUBY METHOD: body.angular_vel -> f32 (radians/sec)
ruby_body_angular_vel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	w := b2.Body_GetAngularVelocity(obj.body_id)
	return mrb.word_boxing_float_value(state, f64(w))
}

// RUBY METHOD: body.angular_vel = rad_per_sec
ruby_body_set_angular_vel :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	w: f64
	mrb.get_args(state, "f", &w)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return mrb.NIL }
	b2.Body_SetAngularVelocity(obj.body_id, f32(w))
	return mrb.word_boxing_float_value(state, w)
}

// RUBY METHOD: body.overlaps?(other_body) -> bool (AABB intersection)
ruby_body_overlaps :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other_val: mrb.Value
	mrb.get_args(state, "o", &other_val)
	me := body_obj(self)
	other := body_obj(other_val)
	if other == nil {
		return mrb.raise_error(state, "TypeError", "overlaps? expected a Body (use obj.body, not obj)")
	}
	if me == nil { return mrb.FALSE }
	if !b2.Shape_IsValid(me.shape_id) || !b2.Shape_IsValid(other.shape_id) { return mrb.FALSE }
	// AABB reject first — practically free, kills the common (far apart) case.
	a := b2.Shape_GetAABB(me.shape_id)
	b := b2.Shape_GetAABB(other.shape_id)
	if a.lowerBound.x > b.upperBound.x || b.lowerBound.x > a.upperBound.x { return mrb.FALSE }
	if a.lowerBound.y > b.upperBound.y || b.lowerBound.y > a.upperBound.y { return mrb.FALSE }

	// AABBs touch — confirm with exact GJK so rotated/circle/poly shapes
	// don't false-positive on bounding-box overlap alone.
	pa := shape_proxy(me.shape_id)
	pb := shape_proxy(other.shape_id)
	if pa.count == 0 || pb.count == 0 { return mrb.TRUE } 	// unsupported shape, keep AABB result
	input := b2.DistanceInput {
		proxyA     = pa,
		proxyB     = pb,
		transformA = b2.Body_GetTransform(b2.Shape_GetBody(me.shape_id)),
		transformB = b2.Body_GetTransform(b2.Shape_GetBody(other.shape_id)),
		useRadii   = true,
	}
	cache := b2.emptySimplexCache
	out := b2.ShapeDistance(input, &cache, nil)
	return out.distance < 1e-4 ? mrb.TRUE : mrb.FALSE
}

// Build a local-space b2.ShapeProxy from a shape. count==0 -> unsupported
// (chain segment); caller decides fallback. Transform applied by ShapeDistance.
shape_proxy :: proc "c" (shape_id: b2.ShapeId) -> b2.ShapeProxy {
	switch b2.Shape_GetType(shape_id) {
	case .circleShape:
		c := b2.Shape_GetCircle(shape_id)
		pts := [1]b2.Vec2{c.center}
		return b2.MakeProxy(pts[:], c.radius)
	case .capsuleShape:
		cap := b2.Shape_GetCapsule(shape_id)
		pts := [2]b2.Vec2{cap.center1, cap.center2}
		return b2.MakeProxy(pts[:], cap.radius)
	case .segmentShape:
		s := b2.Shape_GetSegment(shape_id)
		pts := [2]b2.Vec2{s.point1, s.point2}
		return b2.MakeProxy(pts[:], 0)
	case .polygonShape:
		p := b2.Shape_GetPolygon(shape_id)
		return b2.MakeProxy(p.vertices[:p.count], p.radius)
	case .chainSegmentShape:
		return b2.ShapeProxy{}
	}
	return b2.ShapeProxy{}
}

// RUBY METHOD: body.overlapping -> [GameObject, ...] currently inside this sensor
// Returns the owning GameObjects (not bodies) so game code matches the on_enter
// dispatch shape, which also hands callers the obj.
// Only meaningful for sensor bodies; returns [] otherwise.
ruby_body_overlapping :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	result := mrb.ary_new(g.mrb_state)
	me := body_obj(self)
	if me == nil || !me.sensor || !b2.Shape_IsValid(me.shape_id) { return result }
	cap := b2.Shape_GetSensorCapacity(me.shape_id)
	if cap <= 0 { return result }
	overlaps := make([]b2.ShapeId, int(cap), context.temp_allocator)
	n := b2.Shape_GetSensorOverlaps(me.shape_id, raw_data(overlaps), cap)
	for i in 0 ..< int(n) {
		body := b2.Shape_GetBody(overlaps[i])
		if !b2.Body_IsValid(body) { continue }
		ud := b2.Body_GetUserData(body)
		if ud == nil { continue }
		obj := cast(^Game_Object)ud
		if obj.self_val != mrb.NIL {
			mrb.ary_push(g.mrb_state, result, obj.self_val)
		}
	}
	return result
}

// RUBY METHOD: body.density -> f32 (live from b2 shape)
ruby_body_density :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	return mrb.word_boxing_float_value(state, f64(b2.Shape_GetDensity(obj.shape_id)))
}

// RUBY METHOD: body.density = f
ruby_body_set_density :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) { return mrb.NIL }
	b2.Shape_SetDensity(obj.shape_id, f32(v), true)
	return mrb.word_boxing_float_value(state, v)
}

// RUBY METHOD: body.friction -> f32
ruby_body_friction :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	return mrb.word_boxing_float_value(state, f64(b2.Shape_GetFriction(obj.shape_id)))
}

// RUBY METHOD: body.friction = f
ruby_body_set_friction :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) { return mrb.NIL }
	b2.Shape_SetFriction(obj.shape_id, f32(v))
	return mrb.word_boxing_float_value(state, v)
}

// RUBY METHOD: body.restitution -> f32
ruby_body_restitution :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	return mrb.word_boxing_float_value(state, f64(b2.Shape_GetRestitution(obj.shape_id)))
}

// RUBY METHOD: body.restitution = f
ruby_body_set_restitution :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Shape_IsValid(obj.shape_id) { return mrb.NIL }
	b2.Shape_SetRestitution(obj.shape_id, f32(v))
	return mrb.word_boxing_float_value(state, v)
}

// RUBY METHOD: body.layer = n (single layer; Array/Range also accepted)
ruby_body_set_layer :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	lay := layer_to_bitmask(state, v)
	f := b2.Shape_GetFilter(obj.shape_id)
	f.categoryBits = lay
	b2.Shape_SetFilter(obj.shape_id, f)
	obj.layer = lay
	return v
}

// RUBY METHOD: body.mask = n / [..] / range
ruby_body_set_mask :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	msk := layer_to_bitmask(state, v)
	f := b2.Shape_GetFilter(obj.shape_id)
	f.maskBits = msk
	b2.Shape_SetFilter(obj.shape_id, f)
	obj.mask = msk
	return v
}

// RUBY METHOD: body.type = :static / :kinematic / :dynamic
ruby_body_set_type :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	if !mrb.symbol_p(v) {
		return mrb.raise_error(state, "ArgumentError", "body.type= must be :static, :kinematic, or :dynamic")
	}
	new_type := Body_Type.NONE
	bt: b2.BodyType
	switch mrb.to_string(state, v) {
	case "static":
		new_type = .STATIC
		bt = .staticBody
	case "kinematic":
		new_type = .KINEMATIC
		bt = .kinematicBody
	case "dynamic":
		new_type = .DYNAMIC
		bt = .dynamicBody
	case:
		return mrb.raise_error(state, "ArgumentError", "body.type= must be :static, :kinematic, or :dynamic")
	}

	old_type := obj.body_type
	if new_type == old_type { return v }

	// user-driven (static/kinematic) ⇄ dynamic bookkeeping: keep
	// dynamic_body_count and the user_driven_bodies sync list consistent so
	// physics_body_count and pre-step position sync stay correct.
	old_user_driven := old_type == .STATIC || old_type == .KINEMATIC
	new_user_driven := new_type == .STATIC || new_type == .KINEMATIC
	if old_user_driven && !new_user_driven { untrack_user_driven_body(obj) }
	if !old_user_driven && new_user_driven { track_user_driven_body(obj) }
	if old_type == .DYNAMIC && new_type != .DYNAMIC { dynamic_body_count -= 1 }
	if old_type != .DYNAMIC && new_type == .DYNAMIC { dynamic_body_count += 1 }

	b2.Body_SetType(obj.body_id, bt)
	obj.body_type = new_type
	return v
}

// RUBY METHOD: body.drag -> f32 (linear damping)
ruby_body_drag :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	return mrb.word_boxing_float_value(state, f64(b2.Body_GetLinearDamping(obj.body_id)))
}

// RUBY METHOD: body.drag = f
ruby_body_set_drag :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	b2.Body_SetLinearDamping(obj.body_id, f32(v))
	return mrb.word_boxing_float_value(state, v)
}

// RUBY METHOD: body.ang_drag -> f32 (angular damping)
ruby_body_ang_drag :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.word_boxing_float_value(state, 0)
	}
	return mrb.word_boxing_float_value(state, f64(b2.Body_GetAngularDamping(obj.body_id)))
}

// RUBY METHOD: body.ang_drag = f
ruby_body_set_ang_drag :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: f64
	mrb.get_args(state, "f", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	b2.Body_SetAngularDamping(obj.body_id, f32(v))
	return mrb.word_boxing_float_value(state, v)
}

// RUBY METHOD: body.spin = bool (physics-driven rotation; else fixedRotation)
ruby_body_set_spin :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	new_spin := mrb.boolean(v)
	if new_spin && obj.body_type != .DYNAMIC {
		return mrb.raise_error(state, "ArgumentError", "body.spin = true requires :dynamic")
	}
	b2.Body_SetFixedRotation(obj.body_id, !new_spin)
	obj.spin = new_spin
	return v
}

// RUBY METHOD: body.shape = Circ | Rect (swap collider; body/velocity intact)
ruby_body_set_shape :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}

	new_kind: Physics_Shape_Kind
	half: rl.Vector2
	radius: f32
	offset: rl.Vector2
	if c := extract_or_nil(Circ, v); c != nil {
		new_kind = .CIRCLE
		radius = c.r
		half = {c.r, c.r}
		offset = c.center
	} else if r := extract_or_nil(rl.Rectangle, v); r != nil {
		new_kind = .BOX
		half = {r.width / 2, r.height / 2}
		offset = {r.x + r.width / 2, r.y + r.height / 2}
	} else {
		return mrb.raise_error(state, "TypeError", "body.shape= must be a Circ or Rect")
	}

	rebuild_body_shape(obj, new_kind, half, radius, offset, obj.sensor)

	// Rewire the durable GC root: @__shape on the Body wrapper (self) is the
	// sole keep-alive for the shape Value post-construction (the body() bridge
	// was already dropped in ruby_obj). Overwriting the ivar releases the old
	// Circ/Rect and roots the new one — no gc_register/unregister here.
	obj.shape_val = v
	gc_retain(self, "@__shape", v)
	return v
}

// RUBY METHOD: body.sensor = bool
ruby_body_set_sensor :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	obj := body_obj(self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) {
		return mrb.raise_error(state, "RuntimeError", "physics body has been destroyed")
	}
	new_sensor := mrb.boolean(v)
	if new_sensor == obj.sensor { return v }
	kind, half, radius, offset := shape_descriptor(obj)
	rebuild_body_shape(obj, kind, half, radius, offset, new_sensor)
	return v
}

setup_body :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Body")

	mrb.define_method(g.mrb_state, c, "type", cast(rawptr)ruby_body_type, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "type=", cast(rawptr)ruby_body_set_type, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "shape", cast(rawptr)ruby_body_shape, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "shape=", cast(rawptr)ruby_body_set_shape, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "sensor?", cast(rawptr)ruby_body_sensor, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "sensor=", cast(rawptr)ruby_body_set_sensor, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "spin?", cast(rawptr)ruby_body_spin, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "spin=", cast(rawptr)ruby_body_set_spin, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "layer", cast(rawptr)ruby_body_layer, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "layer=", cast(rawptr)ruby_body_set_layer, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "mask", cast(rawptr)ruby_body_mask, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "mask=", cast(rawptr)ruby_body_set_mask, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "destroy", cast(rawptr)ruby_body_destroy, mrb.ARGS_NONE)

	mrb.define_method(g.mrb_state, c, "overlaps?", cast(rawptr)ruby_body_overlaps, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "overlapping", cast(rawptr)ruby_body_overlapping, mrb.ARGS_NONE)

	mrb.define_method(g.mrb_state, c, "move", cast(rawptr)ruby_body_move, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "apply_force", cast(rawptr)ruby_body_apply_force, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "apply_impulse", cast(rawptr)ruby_body_apply_impulse, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "apply_torque", cast(rawptr)ruby_body_apply_torque, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "drag", cast(rawptr)ruby_body_drag, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "drag=", cast(rawptr)ruby_body_set_drag, mrb.ARGS_REQ(1))

	mrb.define_method(g.mrb_state, c, "density", cast(rawptr)ruby_body_density, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "density=", cast(rawptr)ruby_body_set_density, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "friction", cast(rawptr)ruby_body_friction, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "friction=", cast(rawptr)ruby_body_set_friction, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "restitution", cast(rawptr)ruby_body_restitution, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "restitution=", cast(rawptr)ruby_body_set_restitution, mrb.ARGS_REQ(1))

	mrb.define_method(g.mrb_state, c, "linear_vel", cast(rawptr)ruby_body_linear_vel, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "linear_vel=", cast(rawptr)ruby_body_set_linear_vel, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "angular_vel", cast(rawptr)ruby_body_angular_vel, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "angular_vel=", cast(rawptr)ruby_body_set_angular_vel, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "ang_drag", cast(rawptr)ruby_body_ang_drag, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "ang_drag=", cast(rawptr)ruby_body_set_ang_drag, mrb.ARGS_REQ(1))
}
