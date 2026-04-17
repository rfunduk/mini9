package engine

import "core:c"
import b2 "lib:box2d"
import mrb "lib:mruby"
import rl "vendor:raylib"

Game_Object :: struct {
	pos:       mrb.Value,
	scale:     mrb.Value,
	rotation:  f32,
	visible:   bool,
	// optional physics body (zero-value = no physics)
	body_id:   b2.BodyId,
	shape_id:  b2.ShapeId,
	body_type: Body_Type,
	half_size: rl.Vector2,
	layer:     u64,
	mask:      u64,
}

ruby_gameobject_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		obj := cast(^Game_Object)ptr

		if obj.pos != mrb.NIL { mrb.gc_unregister(state, obj.pos) }
		if obj.scale != mrb.NIL { mrb.gc_unregister(state, obj.scale) }

		if b2.Body_IsValid(obj.body_id) {
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

	// extract physics kwargs (read but don't delete — size/layer/mask stay as dynamic attrs)
	body_type := Body_Type.NONE
	half_size := rl.Vector2{0, 0}
	layer: u64 = 0
	mask: u64 = 0
	density: f32 = 1.0
	friction: f32 = 0.3
	restitution: f32 = 0.0
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

		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.size)
		if val != mrb.NIL {
			sz := extract_native(rl.Vector2, val)
			if sz != nil { half_size = sz^ / 2 }
		}
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
		val = mrb.kwarg(state, kwargs, sym.sensor)
		if val != mrb.NIL { sensor = mrb.boolean(val) }
	}

	pos := create_vector2(pos_vec)
	scale := create_vector2(scale_vec)

	mrb.gc_register(state, pos)
	mrb.gc_register(state, scale)

	// store all the kwargs except those we already handled
	argv := new([1]mrb.Value, context.temp_allocator)
	argv[0] = kwargs

	obj := Game_Object {
		pos       = pos,
		rotation  = rotation,
		scale     = scale,
		visible   = visible,
		body_type = body_type,
		half_size = half_size,
		layer     = layer,
		mask      = mask,
	}

	// create box2d body if physics requested
	if body_type != .NONE {
		obj.body_id, obj.shape_id = create_physics_body(
			body_type,
			pos_vec,
			half_size,
			layer,
			mask,
			density,
			friction,
			restitution,
			sensor,
		)
		if body_type == .DYNAMIC { dynamic_body_count += 1 }
	}

	obj_val := create_game_object(obj, argc, raw_data(argv))

	// store back-reference for dynamic body position sync
	if body_type == .DYNAMIC {
		ptr := extract_native(Game_Object, obj_val)
		if ptr != nil { b2.Body_SetUserData(ptr.body_id, ptr) }
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
			center := b2.Vec2{v.x + obj.half_size.x, v.y + obj.half_size.y}
			b2.Body_SetTransform(obj.body_id, center, b2.Rot_identity)
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
}
