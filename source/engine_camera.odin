package engine

import mrb "lib:mruby"
import rl "lib:raylib"

Camera_Instance :: struct {
	active:          bool,
	rl_camera:       rl.Camera2D,
	original_camera: rl.Camera2D,
}

default_camera :: proc() -> rl.Camera2D {
	return {zoom = 1, target = g.resolution / 2, offset = g.resolution / 2}
}

ruby_camera_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	// note: camera's are not gc'd, but we need a finalizer anyway
	context = global_context
	if ptr != nil { mrb.free(state, ptr) }
}

create_camera :: proc(target: rl.Vector2, zoom: f32, offset: rl.Vector2) -> mrb.Value {
	context = global_context

	initial_camera := rl.Camera2D {
		target = target,
		zoom   = zoom,
		offset = offset,
	}

	// newly created camera becomes the active one
	for cam in g.cameras { cam.active = false }

	camera_ptr := mrb.alloc(
		g.mrb_state,
		Camera_Instance{active = true, rl_camera = initial_camera, original_camera = initial_camera},
	)
	g.camera = initial_camera

	append(&g.cameras, camera_ptr)

	camera_class := mrb.class_get(g.mrb_state, "Camera")
	ruby_obj := mrb.obj_new(g.mrb_state, camera_class, 0, nil)
	mrb.data_init(ruby_obj, camera_ptr, NATIVE_TO_MRUBY_TYPE[Camera_Instance])

	// never gc'd: g.cameras keeps raw ptrs with no removal path, so collecting
	// would free the ptr and dangle. bounded leak: one tiny struct per camera().
	mrb.gc_register(g.mrb_state, ruby_obj)

	return ruby_obj
}

// RUBY FUNCTION: camera(target = nil, zoom = 1, offset = nil) -> creates new Camera
// @engine_method: name="camera", aspec=ARGS_OPT(1)
ruby_camera :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "|H", &kwargs)

	target := g.resolution / 2
	zoom := 1.0
	offset := g.resolution / 2

	{
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.target)
		if val != mrb.NIL { target = extract_or_raise(rl.Vector2, val, "camera: target must be a Vector2")^ }
		val = mrb.kwarg(state, kwargs, sym.offset)
		if val != mrb.NIL { offset = extract_or_raise(rl.Vector2, val, "camera: offset must be a Vector2")^ }
		val = mrb.kwarg(state, kwargs, sym.zoom)
		if val != mrb.NIL { zoom = mrb.to_f64(val) }
	}

	return create_camera(target, f32(zoom), offset)
}

// camera.active =
ruby_camera_set_active :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	active_val: mrb.Value
	mrb.get_args(state, "o", &active_val)

	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }

	// set this camera active and deactivate all others
	is_active := active_val != mrb.NIL && active_val != mrb.FALSE
	if is_active {
		// deactivate all other cameras
		for other_camera in g.cameras { other_camera.active = false }
		g.camera = camera.rl_camera
	} else if camera.active {
		// deactivating the active camera -> restore default
		g.camera = default_camera()
	}
	camera.active = is_active

	return is_active ? mrb.TRUE : mrb.FALSE
}

// camera.active
ruby_camera_get_active :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.FALSE }
	return camera.active ? mrb.TRUE : mrb.FALSE
}

// camera.target =
ruby_camera_set_target :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	target_val: mrb.Value
	mrb.get_args(state, "o", &target_val)

	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }

	if target_val != mrb.NIL {
		camera.rl_camera.target = extract_or_raise(rl.Vector2, target_val, "camera.target= expects a Vector2")^
	} else {
		camera.rl_camera.target = g.resolution / 2
	}

	// always update offset to center the target on screen
	camera.rl_camera.offset = g.resolution / 2

	if camera.active {
		g.camera = camera.rl_camera
	}

	return create_vector2(camera.rl_camera.target)
}

// camera.target
ruby_camera_get_target :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }
	return create_vector2(camera.rl_camera.target)
}

// camera.zoom =
ruby_camera_set_zoom :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	zoom_val: mrb.Value
	mrb.get_args(state, "o", &zoom_val)

	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }

	zoom := mrb.to_f64(zoom_val)
	if zoom <= 0 { zoom = 1.0 }
	camera.rl_camera.zoom = f32(zoom)

	if camera.active {
		g.camera = camera.rl_camera
	}

	return mrb.word_boxing_float_value(state, zoom)
}

// camera.zoom
ruby_camera_get_zoom :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }
	return mrb.word_boxing_float_value(state, f64(camera.rl_camera.zoom))
}

// camera.offset =
ruby_camera_set_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	offset_val: mrb.Value
	mrb.get_args(state, "o", &offset_val)

	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }

	if offset_val != mrb.NIL {
		camera.rl_camera.offset = extract_or_raise(rl.Vector2, offset_val, "camera.offset= expects a Vector2")^
	} else {
		camera.rl_camera.offset = g.resolution / 2
	}

	if camera.active {
		g.camera = camera.rl_camera
	}

	return create_vector2(camera.rl_camera.offset)
}

// camera.offset
ruby_camera_get_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }
	return create_vector2(camera.rl_camera.offset)
}


// camera.reset(target: true, zoom: true)
ruby_camera_reset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	camera := extract_native(Camera_Instance, self)
	if camera == nil { return mrb.NIL }

	// default: reset both target and zoom
	reset_target := true
	reset_zoom := true

	if argc == 1 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.target)
		if val != mrb.NIL { reset_target = val != mrb.FALSE }
		val = mrb.kwarg(state, kwargs, sym.zoom)
		if val != mrb.NIL { reset_zoom = val != mrb.FALSE }
	}

	// reset the specified fields
	if reset_target {
		camera.rl_camera.target = camera.original_camera.target
	}
	if reset_zoom {
		camera.rl_camera.zoom = camera.original_camera.zoom
	}

	// always update offset based on current target to keep it centered
	camera.rl_camera.offset = g.resolution / 2

	if camera.active {
		g.camera = camera.rl_camera
	}

	return mrb.NIL
}

reset_camera_system :: proc() {
	for camera in g.cameras {
		if camera.active {
			camera.rl_camera.offset = g.resolution / 2
			g.camera = camera.rl_camera
			return
		}
	}
}

setup_camera :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Camera")

	mrb.define_method(g.mrb_state, c, "active=", cast(rawptr)ruby_camera_set_active, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "active", cast(rawptr)ruby_camera_get_active, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "target=", cast(rawptr)ruby_camera_set_target, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "target", cast(rawptr)ruby_camera_get_target, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "zoom=", cast(rawptr)ruby_camera_set_zoom, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "zoom", cast(rawptr)ruby_camera_get_zoom, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "offset=", cast(rawptr)ruby_camera_set_offset, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "offset", cast(rawptr)ruby_camera_get_offset, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "reset", cast(rawptr)ruby_camera_reset, mrb.ARGS_OPT(1))

}

cleanup_camera :: proc() {
	delete(g.cameras)
}
