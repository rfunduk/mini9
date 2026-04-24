package engine

import "core:c"
import b2 "lib:box2d"
import mrb "lib:mruby"
import rl "lib:raylib"

Game_Object :: struct {
	self_val:           mrb.Value, // weak back-ref to the mruby object wrapping this struct
	pos:                mrb.Value,
	scale:              mrb.Value,
	rotation:           f32,
	visible:            bool,
	// optional physics body (zero-value = no physics)
	body_id:            b2.BodyId,
	shape_id:           b2.ShapeId,
	body_type:          Body_Type,
	sensor:             bool,
	// mover/AABB half extents — for circles this is {r, r}
	half_size:          rl.Vector2,
	// body center relative to obj.pos (derived from shape kwarg)
	body_center_offset: rl.Vector2,
	// last body-center pushed to box2d — change-detect cache for pre-step sync
	last_sync_center:   rl.Vector2,
	// true once destroy_body has been called — body flushed at end of step
	destroy_queued:     bool,
	layer:              u64,
	mask:               u64,
}

ruby_gameobject_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		obj := cast(^Game_Object)ptr

		if obj.pos != mrb.NIL { mrb.gc_unregister(state, obj.pos) }
		if obj.scale != mrb.NIL { mrb.gc_unregister(state, obj.scale) }

		if b2.Body_IsValid(obj.body_id) {
			// If the body was queued for deferred destroy but GC reaped the
			// obj before flush, drop it from the queue to avoid a dangling
			// pointer next flush.
			if obj.destroy_queued { unqueue_destroy_body(obj) }
			if obj.body_type == .STATIC || obj.body_type == .KINEMATIC {
				untrack_user_driven_body(obj)
			}
			b2.DestroyBody(obj.body_id)
			if obj.body_type == .DYNAMIC { dynamic_body_count -= 1 }
		}

		mrb.free(state, ptr)
	}
}

// RUBY FUNCTION: obj(pos: v2(0), rotation: 0, scale: v2(1), visible: true, ...) -> returns GameObject
// @engine_method: name="obj", arity=-1
ruby_obj :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	pos_vec := rl.Vector2{0, 0}
	rotation: f32 = 0
	scale_vec := rl.Vector2{1, 1}
	visible := true

	if kwargs != mrb.NIL {
		val: mrb.Value

		val = mrb.kwarg(state, kwargs, sym.pos)
		if val != mrb.NIL {
			pos_ptr := extract_native(rl.Vector2, val)
			if pos_ptr == nil {
				return mrb.raise_error(state, "TypeError", "obj: pos must be a Vector2")
			}
			pos_vec = pos_ptr^
			mrb.hash_delete_key(state, kwargs, sym.pos)
		}
		val = mrb.kwarg(state, kwargs, sym.rotation)
		if val != mrb.NIL {
			rotation = f32(mrb.to_f64(val))
			mrb.hash_delete_key(state, kwargs, sym.rotation)
		}
		val = mrb.kwarg(state, kwargs, sym.visible)
		if val != mrb.NIL {
			visible = mrb.boolean(val)
			mrb.hash_delete_key(state, kwargs, sym.visible)
		}
		val = mrb.kwarg(state, kwargs, sym.scale)
		if val != mrb.NIL {
			scale_ptr := extract_native(rl.Vector2, val)
			if scale_ptr == nil {
				return mrb.raise_error(state, "TypeError", "obj: scale must be a Vector2")
			}
			scale_vec = scale_ptr^
			mrb.hash_delete_key(state, kwargs, sym.scale)
		}
	}

	// extract physics kwargs (read but don't delete — layer/mask/sensor stay as dynamic attrs too)
	body_type := Body_Type.NONE
	shape_kind := Physics_Shape_Kind.NONE
	half_size := rl.Vector2{0, 0}
	radius: f32 = 0
	body_center_offset := rl.Vector2{0, 0}
	layer: u64 = 0
	mask: u64 = 0
	density: f32 = 1.0
	friction: f32 = 0.3
	restitution: f32 = 0.0
	drag: f32 = 0.0
	sensor := false

	body_val := mrb.kwarg(state, kwargs, sym.body)
	if body_val != mrb.NIL {
		mrb.hash_delete_key(state, kwargs, sym.body)

		if mrb.symbol_p(body_val) {
			type_str := mrb.to_string(state, body_val)
			switch type_str {
			case "static":
				body_type = .STATIC
			case "kinematic":
				body_type = .KINEMATIC
			case "dynamic":
				body_type = .DYNAMIC
			case:
				return mrb.raise_error(
					state,
					"ArgumentError",
					"body must be :static, :kinematic, or :dynamic",
				)
			}
		}
	}

	val: mrb.Value
	val = mrb.kwarg(state, kwargs, sym.layer)
	if val != mrb.NIL { layer = layer_to_bitmask(state, val) }
	val = mrb.kwarg(state, kwargs, sym.mask)
	if val != mrb.NIL { mask = layer_to_bitmask(state, val) }
	val = mrb.kwarg(state, kwargs, sym.density)
	if val != mrb.NIL { density = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.friction)
	if val != mrb.NIL { friction = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.restitution)
	if val != mrb.NIL { restitution = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.drag)
	if val != mrb.NIL { drag = f32(mrb.to_f64(val)) }
	val = mrb.kwarg(state, kwargs, sym.sensor)
	if val != mrb.NIL { sensor = mrb.boolean(val) }

	// sensor: true with no body type → default to static (trigger zone)
	if sensor && body_type == .NONE { body_type = .STATIC }

	// derive physics shape from `shape:` kwarg (Circ or Rect). Required if body_type != NONE.
	if body_type != .NONE {
		shape_val := mrb.kwarg(state, kwargs, sym.shape)
		if shape_val == mrb.NIL {
			return mrb.raise_error(state, "ArgumentError", "physics body requires a `shape:` (Circ or Rect)")
		}
		if is_native(Circ, shape_val) {
			c := extract_native(Circ, shape_val)
			shape_kind = .CIRCLE
			radius = c.r
			half_size = {c.r, c.r}
			body_center_offset = {c.cx, c.cy}
		} else if is_native(rl.Rectangle, shape_val) {
			r := extract_native(rl.Rectangle, shape_val)
			shape_kind = .BOX
			half_size = {r.width / 2, r.height / 2}
			body_center_offset = {r.x + r.width / 2, r.y + r.height / 2}
		} else {
			return mrb.raise_error(state, "TypeError", "shape: must be a Circ or Rect")
		}
	}

	pos := create_vector2(pos_vec)
	scale := create_vector2(scale_vec)

	mrb.gc_register(state, pos)
	mrb.gc_register(state, scale)

	// store all the kwargs except those we already handled
	argv := new([1]mrb.Value, context.temp_allocator)
	argv[0] = kwargs

	obj := Game_Object {
		pos                = pos,
		rotation           = rotation,
		scale              = scale,
		visible            = visible,
		body_type          = body_type,
		sensor             = sensor,
		half_size          = half_size,
		body_center_offset = body_center_offset,
		last_sync_center   = pos_vec + body_center_offset,
		layer              = layer,
		mask               = mask,
	}

	// create box2d body if physics requested
	if body_type != .NONE {
		obj.body_id, obj.shape_id = create_physics_body(
			body_type,
			pos_vec,
			shape_kind,
			half_size,
			radius,
			body_center_offset,
			layer,
			mask,
			density,
			friction,
			restitution,
			drag,
			sensor,
		)
		if body_type == .DYNAMIC { dynamic_body_count += 1 }
	}

	obj_val := create_game_object(obj, argc, raw_data(argv))

	// store self_val + back-ref on body for sensor/sync lookups
	{
		ptr := extract_native(Game_Object, obj_val)
		if ptr != nil {
			ptr.self_val = obj_val
			if body_type != .NONE {
				b2.Body_SetUserData(ptr.body_id, ptr)
				// Static/kinematic bodies are user-driven — track for pre-step sync
				// so in-place pos mutations propagate to box2d.
				if body_type == .STATIC || body_type == .KINEMATIC {
					track_user_driven_body(ptr)
				}
			}
		}
	}

	if mrb.respond_to(g.mrb_state, obj_val, mrb.intern_cstr(g.mrb_state, "init")) {
		mrb.funcall(g.mrb_state, obj_val, "init", 0)
	}

	return obj_val
}

create_game_object :: proc(go: Game_Object, argc: c.int, argv: rawptr) -> mrb.Value {
	// save current arena state so that we dont lose our kwargs mid-setup
	arena_idx := mrb.gc_arena_save(g.mrb_state)
	defer mrb.gc_arena_restore(g.mrb_state, arena_idx)

	ptr := mrb.alloc(g.mrb_state, go)

	class := mrb.class_get(g.mrb_state, "GameObject")
	ruby_obj := mrb.obj_new(g.mrb_state, class, argc, argv)

	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Game_Object])

	return ruby_obj
}

// RUBY METHOD: o.pos -> gets obj pos
ruby_game_object_get_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.pos
}

// RUBY METHOD: o.scale -> gets obj scale
ruby_game_object_get_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.scale
}

// RUBY METHOD: o.rotation -> gets obj rotation
ruby_game_object_get_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(obj.rotation))
}

// RUBY METHOD: obj.visible -> gets visible flag
ruby_game_object_get_visible :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.visible ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: obj.pos = v2 -> sets obj pos
ruby_game_object_set_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	pos_val: mrb.Value
	mrb.get_args(state, "o", &pos_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	// unregister old, register new
	if obj.pos != mrb.NIL {
		mrb.gc_unregister(state, obj.pos)
	}
	mrb.gc_register(state, pos_val)
	obj.pos = pos_val

	// sync to box2d if physics body exists
	if b2.Body_IsValid(obj.body_id) {
		v := extract_native(rl.Vector2, pos_val)
		if v != nil {
			center := v^ + obj.body_center_offset
			b2.Body_SetTransform(obj.body_id, center, b2.Rot_identity)
			obj.last_sync_center = center
		}
	}

	return pos_val
}

// RUBY METHOD: obj.scale = v2 -> sets obj scale
ruby_game_object_set_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	scale_val: mrb.Value
	mrb.get_args(state, "o", &scale_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	// unregister old, register new
	if obj.scale != mrb.NIL {
		mrb.gc_unregister(state, obj.scale)
	}
	mrb.gc_register(state, scale_val)
	obj.scale = scale_val

	return scale_val
}

// RUBY METHOD: obj.rotation=(angle) -> sets rotation in radians
ruby_game_object_set_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	rotation_val: mrb.Value
	mrb.get_args(state, "o", &rotation_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	obj.rotation = f32(mrb.to_f64(rotation_val))

	return rotation_val
}

// RUBY METHOD: obj.visible = yn -> sets obj visible flag
ruby_game_object_set_visible :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	yn_val: mrb.Value
	mrb.get_args(state, "o", &yn_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	yn := mrb.boolean(yn_val)
	if yn_val != mrb.NIL { obj.visible = yn }

	return yn_val
}

// RUBY METHOD: obj.move(velocity, dt) -> mover API, returns clipped velocity
ruby_game_object_move :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	vel_val: mrb.Value
	dt: f64
	mrb.get_args(state, "of", &vel_val, &dt)

	obj := extract_native(Game_Object, self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return create_vector2({0, 0}) }

	vel := extract_native(rl.Vector2, vel_val)
	if vel == nil { return create_vector2({0, 0}) }

	clipped := physics_move(obj, vel^, f32(dt))
	return create_vector2(clipped)
}

// RUBY METHOD: obj.impulse(v2) -> apply impulse (dynamic bodies)
ruby_game_object_impulse :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	imp_val: mrb.Value
	mrb.get_args(state, "o", &imp_val)

	obj := extract_native(Game_Object, self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return self }

	imp := extract_native(rl.Vector2, imp_val)
	if imp == nil { return self }

	b2.Body_ApplyLinearImpulseToCenter(obj.body_id, {imp.x, imp.y}, true)
	return self
}

// RUBY METHOD: obj.force(v2) -> apply force (dynamic bodies)
ruby_game_object_force :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	force_val: mrb.Value
	mrb.get_args(state, "o", &force_val)

	obj := extract_native(Game_Object, self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return self }

	f := extract_native(rl.Vector2, force_val)
	if f == nil { return self }

	b2.Body_ApplyForceToCenter(obj.body_id, {f.x, f.y}, true)
	return self
}

// RUBY METHOD: obj.velocity -> get linear velocity
ruby_game_object_get_velocity :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return create_vector2({0, 0}) }
	vel := b2.Body_GetLinearVelocity(obj.body_id)
	return create_vector2({vel.x, vel.y})
}

// RUBY METHOD: obj.velocity = v2 -> set linear velocity
ruby_game_object_set_velocity :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	vel_val: mrb.Value
	mrb.get_args(state, "o", &vel_val)

	obj := extract_native(Game_Object, self)
	if obj == nil || !b2.Body_IsValid(obj.body_id) { return mrb.NIL }

	vel := extract_native(rl.Vector2, vel_val)
	if vel == nil { return mrb.NIL }

	b2.Body_SetLinearVelocity(obj.body_id, {vel.x, vel.y})
	return vel_val
}

// RUBY METHOD: obj.destroy_body -> disables the physics body now + queues
// it for full destruction at end of the current physics step. Disabling
// immediately removes the body from simulation (no new contacts/events) but
// keeps shape/body ids valid so other in-flight sensor events in the same
// step can still resolve `other` to this object. Safe to call multiple times.
// User code typically wraps this in its own `destroy` that also removes the
// obj from game-side containers.
ruby_game_object_destroy_body :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	queue_destroy_body(obj)
	return mrb.NIL
}

// RUBY METHOD: obj.overlaps?(other) -> bool (AABB intersection)
ruby_game_object_overlaps :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	other_val: mrb.Value
	mrb.get_args(state, "o", &other_val)

	me := extract_native(Game_Object, self)
	other := extract_native(Game_Object, other_val)
	if me == nil || other == nil { return mrb.FALSE }
	if !b2.Shape_IsValid(me.shape_id) || !b2.Shape_IsValid(other.shape_id) { return mrb.FALSE }

	a := b2.Shape_GetAABB(me.shape_id)
	b := b2.Shape_GetAABB(other.shape_id)
	if a.lowerBound.x > b.upperBound.x || b.lowerBound.x > a.upperBound.x { return mrb.FALSE }
	if a.lowerBound.y > b.upperBound.y || b.lowerBound.y > a.upperBound.y { return mrb.FALSE }
	return mrb.TRUE
}

// RUBY METHOD: obj.overlapping -> [GameObject, ...] currently inside this sensor
// Only meaningful for sensor objects; returns [] otherwise.
ruby_game_object_overlapping :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	result := mrb.ary_new(g.mrb_state)

	me := extract_native(Game_Object, self)
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

setup_game_object :: proc() {
	c := mrb.get_data_class(g.mrb_state, "GameObject")

	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_game_object_get_pos, 0)
	mrb.define_method(g.mrb_state, c, "pos=", cast(rawptr)ruby_game_object_set_pos, 1)
	mrb.define_method(g.mrb_state, c, "rotation", cast(rawptr)ruby_game_object_get_rotation, 0)
	mrb.define_method(g.mrb_state, c, "rotation=", cast(rawptr)ruby_game_object_set_rotation, 1)
	mrb.define_method(g.mrb_state, c, "scale", cast(rawptr)ruby_game_object_get_scale, 0)
	mrb.define_method(g.mrb_state, c, "scale=", cast(rawptr)ruby_game_object_set_scale, 1)
	mrb.define_method(g.mrb_state, c, "visible", cast(rawptr)ruby_game_object_get_visible, 0)
	mrb.define_method(g.mrb_state, c, "visible=", cast(rawptr)ruby_game_object_set_visible, 1)

	// physics methods
	mrb.define_method(g.mrb_state, c, "move", cast(rawptr)ruby_game_object_move, 2)
	mrb.define_method(g.mrb_state, c, "impulse", cast(rawptr)ruby_game_object_impulse, 1)
	mrb.define_method(g.mrb_state, c, "force", cast(rawptr)ruby_game_object_force, 1)
	mrb.define_method(g.mrb_state, c, "velocity", cast(rawptr)ruby_game_object_get_velocity, 0)
	mrb.define_method(g.mrb_state, c, "velocity=", cast(rawptr)ruby_game_object_set_velocity, 1)
	mrb.define_method(g.mrb_state, c, "overlaps?", cast(rawptr)ruby_game_object_overlaps, 1)
	mrb.define_method(g.mrb_state, c, "overlapping", cast(rawptr)ruby_game_object_overlapping, 0)
	mrb.define_method(g.mrb_state, c, "destroy_body", cast(rawptr)ruby_game_object_destroy_body, 0)
}
