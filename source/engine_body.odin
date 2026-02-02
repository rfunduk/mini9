package engine

import "core:math"
import lin "core:math/linalg"
import "core:slice"
import mrb "lib:mruby"
import rl "vendor:raylib"

ruby_body_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		body := cast(^Body)ptr

		if body.size != mrb.NIL { mrb.gc_unregister(state, body.size) }
		if body.offset != mrb.NIL { mrb.gc_unregister(state, body.offset) }
		if body.parent != mrb.NIL { mrb.gc_unregister(state, body.parent) }

		cleanup_body_from_layers(body)

		body_val, ok := g.registered_bodies[body]
		if ok && body_val != mrb.NIL { mrb.gc_unregister(state, body_val) }

		delete_key(&g.registered_bodies, body)
		mrb.free(state, ptr)
	}
}

Body :: struct {
	parent: mrb.Value,
	offset: mrb.Value,
	size:   mrb.Value,
	layer:  Collision_Layer,
	mask:   Collision_Layer,
}

// RUBY FUNCTION: body(offset: v2(0), size: v2(1), layer: [], mask: []) -> returns Body object
// @engine_method: name="body", arity=1
ruby_body :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "H", &kwargs)

	offset := mrb.NIL
	size := mrb.NIL
	layer: Collision_Layer = 0
	mask: Collision_Layer = 0

	if argc == 1 {
		hash := parse_kwargs(state, kwargs)
		if "offset" in hash { offset = hash["offset"] }
		if "size" in hash { size = hash["size"] }
		if "layer" in hash { layer = Collision_Layer(mrb.integer(hash["layer"])) }
		if "mask" in hash { mask = Collision_Layer(mrb.integer(hash["mask"])) }
	}

	if offset == mrb.NIL { offset = create_vector2(rl.Vector2{0, 0}) }
	if size == mrb.NIL { size = create_vector2(rl.Vector2{1, 1}) }

	mrb.gc_register(state, offset)
	mrb.gc_register(state, size)

	body := Body {
		parent = mrb.NIL,
		offset = offset,
		size   = size,
		layer  = layer,
		mask   = mask,
	}

	body_obj := create_body(state, body)
	return body_obj
}

create_body :: proc "c" (state: mrb.State, b: Body) -> mrb.Value {
	context = global_context

	b_ptr := ruby_allocate(Body, b)

	body_class := mrb.class_get(state, "Body")
	ruby_obj := mrb.obj_new(state, body_class, 0, nil)

	mrb.data_init(ruby_obj, b_ptr, NATIVE_TO_MRUBY_TYPE[Body])

	g.registered_bodies[b_ptr] = ruby_obj
	register_body_on_layers(b_ptr)

	return ruby_obj
}

ruby_body_init :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	parent_val: mrb.Value
	mrb.get_args(state, "o", &parent_val)

	mrb.gc_register(state, parent_val)

	body := extract_native(Body, self)
	body.parent = parent_val

	return self
}

// RUBY METHOD: body.offset -> gets body frame offset
ruby_body_get_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }
	return body.offset
}

// RUBY METHOD: body.size -> gets body frame size
ruby_body_get_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }
	return body.size
}

// RUBY METHOD: body.size = v2(10) -> sets body size
ruby_body_set_size :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	size_val: mrb.Value
	mrb.get_args(state, "o", &size_val)

	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }

	size_ptr := extract_native(rl.Vector2, size_val)
	if size_ptr != nil {
		mrb.gc_register(state, size_val)
		mrb.gc_unregister(state, body.size)
		body.size = size_val
	}

	return self
}

// RUBY METHOD: body.offset = v2(10) -> sets body offset
ruby_body_set_offset :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	offset_val: mrb.Value
	mrb.get_args(state, "o", &offset_val)

	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }

	offset_ptr := extract_native(rl.Vector2, offset_val)
	if offset_ptr != nil {
		mrb.gc_register(state, offset_val)
		mrb.gc_unregister(state, body.offset)
		body.offset = offset_val
	}

	return self
}

// RUBY METHOD: body.layer -> gets layer in radians
ruby_body_get_layer :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, i32(body.layer))
}

// RUBY METHOD: body.mask -> gets mask
ruby_body_get_mask :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, i32(body.mask))
}

// RUBY METHOD: body.parent -> gets parent
ruby_body_get_parent :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }
	return body.parent
}

// RUBY METHOD: body.layer=(angle) -> sets layer
ruby_body_set_layer :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	layer: u16
	mrb.get_args(state, "i", &layer)

	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }

	cleanup_body_from_layers(body)
	body.layer = layer
	register_body_on_layers(body)

	return self
}

// RUBY METHOD: body.mask=(angle) -> sets mask in radians
ruby_body_set_mask :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	mask: u16
	mrb.get_args(state, "i", &mask)

	body := extract_native(Body, self)
	if body == nil { return mrb.NIL }

	body.mask = mask

	return self
}

body_to_rect :: proc(b: Body) -> rl.Rectangle {
	offset := extract_native(rl.Vector2, b.offset)
	size := extract_native(rl.Vector2, b.size)
	pos := body_get_parent_pos(g.mrb_state, b.parent)
	return {math.floor(pos.x + offset.x), math.floor(pos.y + offset.y), size.x, size.y}
}

body_get_parent_pos :: proc(state: mrb.State, ruby_obj: mrb.Value) -> (pos: rl.Vector2) {
	if ruby_obj != mrb.NIL {
		pos_sym := mrb.intern_cstr(g.mrb_state, "pos")
		if mrb.respond_to(g.mrb_state, ruby_obj, pos_sym) {
			arena_idx := mrb.gc_arena_save(g.mrb_state)
			defer mrb.gc_arena_restore(g.mrb_state, arena_idx)
			pos_val := mrb.funcall(g.mrb_state, ruby_obj, "pos", 0)
			pos = extract_native(rl.Vector2, pos_val)^
		}
	}
	return
}

// RUBY METHOD: body.resolve_collisions(velocity, slide: yn) -> detects and resolves collisions, optionally sliding
ruby_body_resolve_collisions :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	body := extract_native(Body, self)

	velocity_val, kwargs: mrb.Value
	dt: f64
	argc := mrb.get_args(g.mrb_state, "of|H", &velocity_val, &dt, &kwargs)

	velocity := extract_native(rl.Vector2, velocity_val)^

	slide := false
	if argc == 2 && kwargs != mrb.NIL {
		hash := parse_kwargs(g.mrb_state, kwargs)
		if "slide" in hash { slide = mrb.boolean(hash["slide"]) }
	}

	collisions := make([dynamic]Collision_Info)

	for other in get_bodies_for_mask(body) {
		info := body_vs_body(body, other, velocity, dt)
		if info.hit { append(&collisions, info) }
	}

	// sort collisions by time
	slice.sort_by(collisions[:], collision_info_order)

	// resolve collisions
	cinfo_array := mrb.ary_new(g.mrb_state)
	first_collision_resolved := false
	first_collision_normal: rl.Vector2

	for info in collisions {
		// after first t=0 collision, filter out similar normals
		if first_collision_resolved && abs(info.t) < 0.001 {
			dot := lin.dot(info.normal, first_collision_normal)
			if abs(dot) > 0.5 { 	// normals pointing in similar direction (within ~60 degrees)
				// fmt.printfln("\t\tSKIPPING similar collision: dot=%v, normal=%v vs %v", dot, info.normal, first_collision_normal)
				continue
			}
		}

		velocity += info.normal * lin.abs(velocity) * (1 - info.t)

		mrb.ary_push(g.mrb_state, cinfo_array, create_collision_info(info))

		// track first t=0 collision for filtering
		if !first_collision_resolved && abs(info.t) < 0.001 {
			first_collision_resolved = true
			first_collision_normal = info.normal
		}
	}

	result_array := mrb.ary_new(g.mrb_state)
	mrb.ary_push(g.mrb_state, result_array, create_vector2(velocity))
	mrb.ary_push(g.mrb_state, result_array, cinfo_array)

	return result_array
}

collision_info_order :: proc(lhs, rhs: Collision_Info) -> bool {
	return lhs.sort_t < rhs.sort_t
}

setup_body :: proc() {
	c := create_data_class("Body")

	mrb.define_method(g.mrb_state, c, "init", cast(rawptr)ruby_body_init, 1)

	// getters
	mrb.define_method(g.mrb_state, c, "offset", cast(rawptr)ruby_body_get_offset, 0)
	mrb.define_method(g.mrb_state, c, "size", cast(rawptr)ruby_body_get_size, 0)
	mrb.define_method(g.mrb_state, c, "layer", cast(rawptr)ruby_body_get_layer, 0)
	mrb.define_method(g.mrb_state, c, "mask", cast(rawptr)ruby_body_get_mask, 0)
	mrb.define_method(g.mrb_state, c, "parent", cast(rawptr)ruby_body_get_parent, 0)
	mrb.define_method(g.mrb_state, c, "resolve_collisions", cast(rawptr)ruby_body_resolve_collisions, -1)

	// setters
	mrb.define_method(g.mrb_state, c, "offset=", cast(rawptr)ruby_body_set_offset, 1)
	mrb.define_method(g.mrb_state, c, "size=", cast(rawptr)ruby_body_set_size, 1)
	mrb.define_method(g.mrb_state, c, "layer=", cast(rawptr)ruby_body_set_layer, 1)
	mrb.define_method(g.mrb_state, c, "mask=", cast(rawptr)ruby_body_set_mask, 1)
}

register_body_on_layers :: proc(b: ^Body) {
	if b.layer > 0 {
		for bit in 0 ..< u8(size_of(Collision_Layer) * 8) {
			layer := Collision_Layer(1 << bit)
			// not on this layer
			if (b.layer & layer) == 0 { continue }

			// create list if needed
			if layer not_in g.bodies_by_layer {
				g.bodies_by_layer[layer] = make([dynamic]^Body)
			}

			append(&g.bodies_by_layer[layer], b)
		}
	}
}

cleanup_body_from_layers :: proc(b: ^Body) {
	if b.layer > 0 {
		for bit in 0 ..< u8(size_of(Collision_Layer) * 8) {
			layer := Collision_Layer(1 << bit)

			// not on this layer
			if (b.layer & layer) == 0 { continue }

			bodies_on_layer := &g.bodies_by_layer[layer]
			for x, i in bodies_on_layer {
				if x == b { unordered_remove(bodies_on_layer, i);break }
			}
		}
	}
}

get_bodies_for_mask :: proc(b: ^Body) -> [dynamic]^Body {
	result := make([dynamic]^Body)

	// why check collisions for an object with no mask?
	if b.mask <= 0 { return result }

	seen := make(map[^Body]bool)
	defer delete(seen)

	for bit in 0 ..< u8(size_of(Collision_Layer) * 8) {
		layer := Collision_Layer(1 << bit)
		// invalid layer
		if layer not_in g.bodies_by_layer { continue }

		// not interested in this layer
		if (b.mask & layer) == 0 { continue }

		for other_body in g.bodies_by_layer[layer] {
			// skip self
			if other_body == b { continue }

			// already included
			if other_body in seen { continue }

			// keep track for de-duping
			seen[other_body] = true

			append(&result, other_body)
		}
	}

	return result
}
