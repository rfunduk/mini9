package engine

import "core:c"
import "core:math"
import mrb "lib:mruby"
import rl "vendor:raylib"

Game_Object :: struct {
	pos:      mrb.Value,
	scale:    mrb.Value,
	rotation: f32,
	visible:  bool,
}

ruby_gameobject_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		obj := cast(^Game_Object)ptr

		if obj.pos != mrb.NIL { mrb.gc_unregister(state, obj.pos) }
		if obj.scale != mrb.NIL { mrb.gc_unregister(state, obj.scale) }

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
		hash := parse_kwargs(state, kwargs)

		if "pos" in hash {
			pos_vec = extract_native(rl.Vector2, hash["pos"])^
			ruby_hash_delete(state, kwargs, "pos")
		}
		if "rotation" in hash {
			rotation = f32(to_f64(hash["rotation"]))
			ruby_hash_delete(state, kwargs, "rotation")
		}
		if "visible" in hash {
			visible = mrb.boolean(hash["visible"])
			ruby_hash_delete(state, kwargs, "visible")
		}
		if "scale" in hash {
			// TODO check and handle error here
			scale_vec = extract_native(rl.Vector2, hash["scale"])^
			ruby_hash_delete(state, kwargs, "scale")
		}
	}

	pos := create_vector2(pos_vec)
	scale := create_vector2(scale_vec)

	// protect from GC since we're storing them in Odin struct
	mrb.gc_register(state, pos)
	mrb.gc_register(state, scale)

	// store all the kwargs except those we already handled
	argv := new([1]mrb.Value, context.temp_allocator)
	argv[0] = kwargs

	obj := Game_Object {
		pos      = pos,
		rotation = rotation,
		scale    = scale,
		visible  = visible,
	}
	obj_val := create_game_object(obj, argc, raw_data(argv))

	if mrb.respond_to(g.mrb_state, obj_val, mrb.intern_cstr(g.mrb_state, "init")) {
		mrb.funcall(g.mrb_state, obj_val, "init", 0)
	}

	return obj_val
}

create_game_object :: proc(go: Game_Object, argc: c.int, argv: rawptr) -> mrb.Value {
	// save current arena state so that we dont lose our kwargs mid-setup
	arena_idx := mrb.gc_arena_save(g.mrb_state)
	defer mrb.gc_arena_restore(g.mrb_state, arena_idx)

	ptr := ruby_allocate(Game_Object, go)

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

// RUBY METHOD: obj.rotation_degrees -> gets rotation in degrees
ruby_game_object_get_rotation_deg :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(obj.rotation * 180.0 / math.PI))
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

	obj.rotation = f32(to_f64(rotation_val))

	return rotation_val
}

// RUBY METHOD: obj.rotation_degrees=(angle) -> sets rotation in degrees
ruby_game_object_set_rotation_deg :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	rotation_val: mrb.Value
	mrb.get_args(state, "o", &rotation_val)

	obj := extract_native(Game_Object, self)
	if obj == nil { return mrb.NIL }

	obj.rotation = f32(to_f64(rotation_val) * math.PI / 180.0)

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

setup_game_object :: proc() {
	c := create_data_class("GameObject")

	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_game_object_get_pos, 0)
	mrb.define_method(g.mrb_state, c, "pos=", cast(rawptr)ruby_game_object_set_pos, 1)
	mrb.define_method(g.mrb_state, c, "rotation", cast(rawptr)ruby_game_object_get_rotation, 0)
	mrb.define_method(g.mrb_state, c, "rotation=", cast(rawptr)ruby_game_object_set_rotation, 1)
	mrb.define_method(g.mrb_state, c, "rotation_degrees", cast(rawptr)ruby_game_object_get_rotation_deg, 0)
	mrb.define_method(g.mrb_state, c, "rotation_degrees=", cast(rawptr)ruby_game_object_set_rotation_deg, 1)
	mrb.define_method(g.mrb_state, c, "scale", cast(rawptr)ruby_game_object_get_scale, 0)
	mrb.define_method(g.mrb_state, c, "scale=", cast(rawptr)ruby_game_object_set_scale, 1)
	mrb.define_method(g.mrb_state, c, "visible", cast(rawptr)ruby_game_object_get_visible, 0)
	mrb.define_method(g.mrb_state, c, "visible=", cast(rawptr)ruby_game_object_set_visible, 1)
}
