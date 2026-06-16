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
	// optional physics body (zero-value = no physics). The Ruby surface is
	// `obj.body` — a thin wrapper holding a pointer to this struct.
	body_id:            b2.BodyId,
	shape_id:           b2.ShapeId,
	body_type:          Body_Type,
	body_val:           mrb.Value, // Body wrapper (mrb.NIL if no physics)
	shape_val:          mrb.Value, // Circ/Rect retained for body.shape getter
	sensor:             bool,
	spin:               bool, // opt-in physics-driven rotation (else fixedRotation)
	// mover/AABB half extents — for circles this is {r, r}
	half_size:          rl.Vector2,
	// body center relative to obj.pos (derived from shape kwarg)
	body_center_offset: rl.Vector2,
	// last body-center pushed to box2d — change-detect cache for pre-step sync
	last_sync_center:   rl.Vector2,
	last_sync_rotation: f32,
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
		// body_val/shape_val are kept alive by hidden ivars (gc_link/gc_retain),
		// not gc_register roots — nothing to unregister here.

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

// RUBY FUNCTION: obj(pos: v2(0), rotation: 0, scale: v2(1), visible: true, body: body(...), ...) -> returns GameObject
// @engine_method: name="obj", aspec=ARGS_OPT(1)
ruby_obj :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	pos_vec := rl.Vector2{0, 0}
	rotation: f32 = 0
	scale_vec := rl.Vector2{1, 1}
	visible := true
	// Copied by value so we don't depend on the BodySpec's lifetime past the
	// kwarg extraction. The BodySpec is bridged (gc_register below) only until
	// the durable obj<->body<->shape chain is built; the shape rides its
	// @__shape ivar across that window. body_spec_val carries the bridged
	// BodySpec down to the matching gc_unregister.
	spec: Body_Spec
	have_spec := false
	body_spec_val := mrb.NIL

	if kwargs != mrb.NIL {
		val: mrb.Value

		val = mrb.kwarg(state, kwargs, sym.pos)
		if val != mrb.NIL {
			pos_vec = extract_or_raise(rl.Vector2, val, "obj: pos must be a Vector2")^
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
			scale_vec = extract_or_raise(rl.Vector2, val, "obj: scale must be a Vector2")^
			mrb.hash_delete_key(state, kwargs, sym.scale)
		}
		val = mrb.kwarg(state, kwargs, sym.body)
		if val != mrb.NIL {
			spec = extract_or_raise(Body_Spec, val, "obj: body: must come from body(...)")^
			have_spec = true
			// FRAGILE — half 1 of 2; paired with the gc_unregister in the
			// durable-chain block below. Root the BodySpec across the window
			// between deleting the `body:` kwarg (its only other root) and
			// wiring the lasting chain. The shape rides the BodySpec's @__shape
			// ivar, so rooting the spec keeps the shape reachable too.
			mrb.gc_register(state, val)
			body_spec_val = val
			mrb.hash_delete_key(state, kwargs, sym.body)
		}
	}

	// Arena-bound the rest of the call (allocs from here on): create_vector2,
	// create_game_object, body wrapper, funcall(init). Placed after the kwarg
	// raise sites — defer would be skipped by longjmp from raise_error.
	arena_idx := mrb.gc_arena_save(g.mrb_state)
	defer mrb.gc_arena_restore(g.mrb_state, arena_idx)

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
		body_val           = mrb.NIL,
		shape_val          = mrb.NIL,
		last_sync_center   = pos_vec,
		last_sync_rotation = rotation,
	}

	if have_spec {
		obj.body_type = spec.body_type
		obj.sensor = spec.sensor
		obj.spin = spec.spin
		obj.half_size = spec.half_size
		obj.body_center_offset = spec.body_center_offset
		obj.last_sync_center = pos_vec + spec.body_center_offset
		obj.layer = spec.layer
		obj.mask = spec.mask
		obj.shape_val = spec.shape_val
		obj.body_id, obj.shape_id = create_physics_body(
			spec.body_type,
			pos_vec,
			rotation,
			spec.shape_kind,
			spec.half_size,
			spec.radius,
			spec.body_center_offset,
			spec.layer,
			spec.mask,
			spec.density,
			spec.friction,
			spec.restitution,
			spec.drag,
			spec.ang_drag,
			spec.sensor,
			spec.spin,
		)
		if spec.body_type == .DYNAMIC { dynamic_body_count += 1 }
	}

	obj_val := create_game_object(obj, argc, raw_data(argv))

	// store self_val + back-ref on body for sensor/sync lookups
	{
		ptr := extract_native(Game_Object, obj_val)
		if ptr != nil {
			ptr.self_val = obj_val
			if ptr.body_type != .NONE {
				b2.Body_SetUserData(ptr.body_id, ptr)
				// Static/kinematic bodies are user-driven — track for pre-step sync
				// so in-place pos mutations propagate to box2d.
				if ptr.body_type == .STATIC || ptr.body_type == .KINEMATIC {
					track_user_driven_body(ptr)
				}
				ptr.body_val = create_body_wrapper(ptr)
				// FRAGILE — half 2 of 2; paired with the gc_register above.
				// ORDER IS LOAD-BEARING: build the durable chain FIRST, then
				// drop the BodySpec bridge. Until the chain exists, the shape
				// is only reachable via the bridged BodySpec; reordering or
				// skipping any line below reintroduces a use-after-free where
				// shape (and Body.obj) come back as a recycled String/garbage.
				//
				// 1. GameObject <-> Body co-reachable: holding either from
				//    script keeps both valid; swept together once neither is
				//    held. (Cycle is fine — mruby GC is mark-sweep.)
				gc_link(obj_val, "@__body", ptr.body_val, "@__obj")
				// 2. Shape rides the Body's @__shape ivar. Now reachable via
				//    obj_val (caller-held) <-> body_val -> shape for as long
				//    as either the obj or its body is referenced.
				gc_retain(ptr.body_val, "@__shape", ptr.shape_val)
				// 3. Durable chain exists and is rooted by the caller's
				//    reference to obj_val — only now is it safe to drop the
				//    BodySpec bridge installed above.
				if body_spec_val != mrb.NIL { mrb.gc_unregister(state, body_spec_val) }
			}
		}
	}

	if mrb.respond_to(g.mrb_state, obj_val, mrb.intern_cstr(g.mrb_state, "init")) {
		mrb.funcall(g.mrb_state, obj_val, "init", 0)
	}

	return obj_val
}

// Allocates the native Game_Object, creates the ruby wrapper, and binds the
// native data. Caller is responsible for arena scoping — every caller does
// post-create work (body wrapper, funcall, etc.) that allocates and could
// otherwise GC the freshly-minted value.
create_game_object :: proc(go: Game_Object, argc: c.int, argv: rawptr) -> mrb.Value {
	ptr := mrb.alloc(g.mrb_state, go)

	class := mrb.class_get(g.mrb_state, "GameObject")
	ruby_obj := mrb.obj_new(g.mrb_state, class, argc, argv)

	mrb.data_init(ruby_obj, ptr, NATIVE_TO_MRUBY_TYPE[Game_Object])

	return ruby_obj
}

// RUBY METHOD: o.pos -> gets obj pos
ruby_go_get_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.pos
}

// RUBY METHOD: o.scale -> gets obj scale
ruby_go_get_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.scale
}

// RUBY METHOD: o.rotation -> gets obj rotation
ruby_go_get_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(obj.rotation))
}

// RUBY METHOD: obj.visible -> gets visible flag
ruby_go_get_visible :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.visible ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: obj.pos = v2 -> sets obj pos
ruby_go_set_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
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
			b2.Body_SetTransform(obj.body_id, center, b2.MakeRot(obj.rotation))
			obj.last_sync_center = center
			obj.last_sync_rotation = obj.rotation
		}
	}

	return pos_val
}

// RUBY METHOD: obj.scale = v2 -> sets obj scale
ruby_go_set_scale :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
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
ruby_go_set_rotation :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	rotation_val: mrb.Value
	mrb.get_args(state, "o", &rotation_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	obj.rotation = f32(mrb.to_f64(rotation_val))

	if b2.Body_IsValid(obj.body_id) {
		pos := b2.Body_GetPosition(obj.body_id)
		b2.Body_SetTransform(obj.body_id, pos, b2.MakeRot(obj.rotation))
		obj.last_sync_rotation = obj.rotation
	}

	return rotation_val
}

// RUBY METHOD: obj.visible = yn -> sets obj visible flag
ruby_go_set_visible :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	yn_val: mrb.Value
	mrb.get_args(state, "o", &yn_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	yn := mrb.boolean(yn_val)
	if yn_val != mrb.NIL { obj.visible = yn }

	return yn_val
}

// RUBY METHOD: obj.body -> Body | nil
ruby_go_get_body :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return obj.body_val
}

setup_game_object :: proc() {
	c := mrb.get_data_class(g.mrb_state, "GameObject")

	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_go_get_pos, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "pos=", cast(rawptr)ruby_go_set_pos, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "rotation", cast(rawptr)ruby_go_get_rotation, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "rotation=", cast(rawptr)ruby_go_set_rotation, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "scale", cast(rawptr)ruby_go_get_scale, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "scale=", cast(rawptr)ruby_go_set_scale, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "visible", cast(rawptr)ruby_go_get_visible, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "visible=", cast(rawptr)ruby_go_set_visible, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "body", cast(rawptr)ruby_go_get_body, mrb.ARGS_NONE)
}
