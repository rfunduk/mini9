package engine

import "core:math"
import "core:math/rand"
import mrb "lib:mruby"
import rl "lib:raylib"

@(private = "file")
RAD_TO_DEG :: 180.0 / math.PI

@(private = "file")
particles_list: [dynamic]^Particles_Instance

@(private = "file")
parse_shape :: proc(v: mrb.Value) -> Shape_Kind {
	switch v {
	case sym.rect:
		return .Rect
	case sym.circle:
		return .Circle
	case sym.line:
		return .Line
	}
	return .Pixel
}

Shape_Kind :: enum {
	Pixel,
	Rect,
	Circle,
	Line,
}

Curve_Elem :: enum {
	F,
	V2,
	Color,
}

Curve :: struct {
	arr:  mrb.Value,
	len:  i32,
	elem: Curve_Elem,
}

Prop_Spec :: union {
	f32,
	rl.Vector2,
	rl.Color,
	^Sampler,
	^rl.Rectangle,
	^Circ,
	Curve,
}

Prop :: struct {
	spec: Prop_Spec,
	ref:  mrb.Value, // gc-registered ruby obj (NIL when not needed)
}

Particles_Instance :: struct {
	ruby_obj:       mrb.Value,
	max:            i32,
	count:          i32,
	head:           i32,
	rate:           f32,
	accum:          f32,
	running:        bool,
	destroyed:      bool,
	shape:          Shape_Kind,

	// specs
	lifetime:       Prop,
	pos_spec:       Prop,
	vel_spec:       Prop,
	accel_spec:     Prop,
	rot_spec:       Prop,
	ang_vel_spec:   Prop,
	ang_accel_spec: Prop,
	size_spec:      Prop,
	color_spec:     Prop,
	drag_spec:      Prop,
	ang_drag_spec:  Prop,

	// SOA
	pos:            []rl.Vector2,
	vel:            []rl.Vector2,
	accel:          []rl.Vector2,
	rot:            []f32,
	ang_vel:        []f32,
	ang_accel:      []f32,
	life:           []f32,
	max_life:       []f32,
}

PARTICLE_PROPS :: 11

ruby_particles_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr == nil { return }
	p := cast(^Particles_Instance)ptr
	particles_unregister_refs(state, p)
	particles_free_storage(p)
	mrb.free(state, ptr)
}

@(private = "file")
particles_unregister_refs :: proc(state: mrb.State, p: ^Particles_Instance) {
	props := [PARTICLE_PROPS]^Prop {
		&p.lifetime,
		&p.pos_spec,
		&p.vel_spec,
		&p.accel_spec,
		&p.rot_spec,
		&p.ang_vel_spec,
		&p.size_spec,
		&p.color_spec,
		&p.drag_spec,
		&p.ang_drag_spec,
		&p.ang_accel_spec,
	}
	for prop in props {
		if prop.ref != mrb.NIL { mrb.gc_unregister(state, prop.ref) }
	}
}

@(private = "file")
particles_free_storage :: proc(p: ^Particles_Instance) {
	delete(p.pos)
	delete(p.vel)
	delete(p.accel)
	delete(p.rot)
	delete(p.ang_vel)
	delete(p.ang_accel)
	delete(p.life)
	delete(p.max_life)
	p.pos = nil
	p.vel = nil
	p.accel = nil
	p.rot = nil
	p.ang_vel = nil
	p.ang_accel = nil
	p.life = nil
	p.max_life = nil
}

@(private = "file")
particles_alloc_storage :: proc(p: ^Particles_Instance) {
	n := int(p.max)
	p.pos = make([]rl.Vector2, n)
	p.vel = make([]rl.Vector2, n)
	p.accel = make([]rl.Vector2, n)
	p.rot = make([]f32, n)
	p.ang_vel = make([]f32, n)
	p.ang_accel = make([]f32, n)
	p.life = make([]f32, n)
	p.max_life = make([]f32, n)
}

// Parse a ruby value into a Prop. Type-sniffs to determine variant.
@(private = "file")
parse_prop :: proc(val: mrb.Value, allow_shapes: bool = false) -> Prop {
	if val == mrb.NIL { return {ref = mrb.NIL} }

	if is_native(Sampler, val) {
		mrb.gc_register(g.mrb_state, val)
		return {spec = extract_native(Sampler, val), ref = val}
	}
	if mrb.array_p(val) {
		n := i32(mrb.ary_len(val))
		if n >= 2 {
			mrb.gc_register(g.mrb_state, val)
			first := mrb.ary_entry(val, 0)
			elem: Curve_Elem
			if is_native(rl.Vector2, first) {
				elem = .V2
			} else if is_native(rl.Color, first) {
				elem = .Color
			} else {
				elem = .F
			}
			return {spec = Curve{arr = val, len = n, elem = elem}, ref = val}
		}
	}
	if allow_shapes && is_native(rl.Rectangle, val) {
		mrb.gc_register(g.mrb_state, val)
		return {spec = extract_native(rl.Rectangle, val), ref = val}
	}
	if allow_shapes && is_native(Circ, val) {
		mrb.gc_register(g.mrb_state, val)
		return {spec = extract_native(Circ, val), ref = val}
	}
	if is_native(rl.Color, val) {
		cp := extract_native(rl.Color, val)
		if cp != nil { return {spec = cp^, ref = mrb.NIL} }
	}
	if is_native(rl.Vector2, val) {
		vp := extract_native(rl.Vector2, val)
		if vp != nil { return {spec = vp^, ref = mrb.NIL} }
	}
	// numeric fallback
	return {spec = f32(mrb.to_f64(val)), ref = mrb.NIL}
}

// Sample a float at spawn time.
@(private = "file")
sample_f :: #force_inline proc(p: Prop, default: f32) -> f32 {
	switch v in p.spec {
	case f32:
		return v
	case ^Sampler:
		return sampler_sample_f(v)
	case Curve:
		return f32(mrb.to_f64(mrb.ary_entry(v.arr, 0)))
	case rl.Vector2, rl.Color, ^rl.Rectangle, ^Circ:
		return default
	}
	return default
}

// Sample a v2 at spawn time.
@(private = "file")
sample_v2 :: #force_inline proc(p: Prop, default: rl.Vector2) -> rl.Vector2 {
	switch v in p.spec {
	case rl.Vector2:
		return v
	case ^Sampler:
		return sampler_sample_v2(v)
	case ^rl.Rectangle:
		return {v.x + rand.float32() * v.width, v.y + rand.float32() * v.height}
	case ^Circ:
		theta := rand.float32() * 2 * math.PI
		radius := math.sqrt(rand.float32()) * v.r
		return {v.cx + radius * math.cos(theta), v.cy + radius * math.sin(theta)}
	case Curve:
		if v.elem == .V2 {
			vp := extract_native(rl.Vector2, mrb.ary_entry(v.arr, 0))
			if vp != nil { return vp^ }
		}
		return default
	case f32, rl.Color:
		return default
	}
	return default
}

// Resolve a curve at normalized time t into adjacent indices + fractional weight.
@(private = "file")
curve_lookup :: #force_inline proc(c: Curve, t: f32) -> (lo, hi: i32, frac: f32) {
	fi := t * f32(c.len - 1)
	lo = i32(fi)
	hi = min(lo + 1, c.len - 1)
	frac = fi - f32(lo)
	return
}

// Eval float curve at normalized time t (0..1).
@(private = "file")
eval_f :: #force_inline proc(p: Prop, t: f32, default: f32) -> f32 {
	switch v in p.spec {
	case f32:
		return v
	case Curve:
		lo, hi, frac := curve_lookup(v, t)
		a := f32(mrb.to_f64(mrb.ary_entry(v.arr, lo)))
		b := f32(mrb.to_f64(mrb.ary_entry(v.arr, hi)))
		return a + frac * (b - a)
	case rl.Vector2, rl.Color, ^Sampler, ^rl.Rectangle, ^Circ:
		return default
	}
	return default
}

// Eval v2 curve at normalized time t (0..1).
@(private = "file")
eval_v2 :: #force_inline proc(p: Prop, t: f32, default: rl.Vector2) -> rl.Vector2 {
	switch v in p.spec {
	case rl.Vector2:
		return v
	case Curve:
		lo, hi, frac := curve_lookup(v, t)
		a := extract_native(rl.Vector2, mrb.ary_entry(v.arr, lo))
		b := extract_native(rl.Vector2, mrb.ary_entry(v.arr, hi))
		if a == nil { return default }
		if b == nil { return a^ }
		return {a.x + frac * (b.x - a.x), a.y + frac * (b.y - a.y)}
	case f32, rl.Color, ^Sampler, ^rl.Rectangle, ^Circ:
		return default
	}
	return default
}

// Eval color curve at normalized time t (0..1).
@(private = "file")
eval_color :: #force_inline proc(p: Prop, t: f32, default: rl.Color) -> rl.Color {
	switch v in p.spec {
	case rl.Color:
		return v
	case Curve:
		lo, hi, frac := curve_lookup(v, t)
		a := extract_native(rl.Color, mrb.ary_entry(v.arr, lo))
		b := extract_native(rl.Color, mrb.ary_entry(v.arr, hi))
		if a == nil { return default }
		if b == nil { return a^ }
		return {
			u8(f32(a.r) + frac * f32(i16(b.r) - i16(a.r))),
			u8(f32(a.g) + frac * f32(i16(b.g) - i16(a.g))),
			u8(f32(a.b) + frac * f32(i16(b.b) - i16(a.b))),
			u8(f32(a.a) + frac * f32(i16(b.a) - i16(a.a))),
		}
	case f32, rl.Vector2, ^Sampler, ^rl.Rectangle, ^Circ:
		return default
	}
	return default
}

// Eval size spec — dispatches to f or v2 based on curve elem type.
@(private = "file")
eval_size :: #force_inline proc(p: Prop, t: f32, default: rl.Vector2) -> rl.Vector2 {
	switch v in p.spec {
	case rl.Vector2:
		return v
	case f32:
		return {v, v}
	case Curve:
		if v.elem == .V2 { return eval_v2(p, t, default) }
		s := eval_f(p, t, 1)
		return {s, s}
	case rl.Color, ^Sampler, ^rl.Rectangle, ^Circ:
		return default
	}
	return default
}

// RUBY FUNCTION: particles(max:, rate:, lifetime:, pos:, ...) -> Particles
// @engine_method: name="particles", aspec=ARGS_REQ(1)
ruby_particles :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	kwargs: mrb.Value
	mrb.get_args(state, "H", &kwargs)

	max_v := mrb.kwarg(state, kwargs, sym.max)
	if max_v == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "particles: missing required kwarg :max")
	}
	rate_v := mrb.kwarg(state, kwargs, sym.rate)
	if rate_v == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "particles: missing required kwarg :rate")
	}
	life_v := mrb.kwarg(state, kwargs, sym.lifetime)
	if life_v == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "particles: missing required kwarg :lifetime")
	}
	pos_v := mrb.kwarg(state, kwargs, sym.pos)
	if pos_v == mrb.NIL {
		return mrb.raise_error(state, "ArgumentError", "particles: missing required kwarg :pos")
	}

	max_i := i32(mrb.to_f64(max_v))
	if max_i <= 0 {
		return mrb.raise_error(state, "ArgumentError", "particles: :max must be > 0")
	}

	p := Particles_Instance {
		max            = max_i,
		rate           = f32(mrb.to_f64(rate_v)),
		lifetime       = parse_prop(life_v),
		pos_spec       = parse_prop(pos_v, allow_shapes = true),
		vel_spec       = parse_prop(mrb.kwarg(state, kwargs, sym.velocity)),
		accel_spec     = parse_prop(mrb.kwarg(state, kwargs, sym.accel)),
		rot_spec       = parse_prop(mrb.kwarg(state, kwargs, sym.rotation)),
		ang_vel_spec   = parse_prop(mrb.kwarg(state, kwargs, sym.ang_vel)),
		ang_accel_spec = parse_prop(mrb.kwarg(state, kwargs, sym.ang_accel)),
		size_spec      = parse_prop(mrb.kwarg(state, kwargs, sym.size)),
		color_spec     = parse_prop(mrb.kwarg(state, kwargs, sym.color)),
		drag_spec      = parse_prop(mrb.kwarg(state, kwargs, sym.drag)),
		ang_drag_spec  = parse_prop(mrb.kwarg(state, kwargs, sym.ang_drag)),
		shape          = .Pixel,
		running        = true,
	}

	if v := mrb.kwarg(state, kwargs, sym.shape); v != mrb.NIL {
		p.shape = parse_shape(v)
	}
	if v := mrb.kwarg(state, kwargs, sym.start); v != mrb.NIL {
		p.running = mrb.boolean(v)
	}

	pptr := mrb.alloc(g.mrb_state, p)
	particles_alloc_storage(pptr)

	cls := mrb.class_get(g.mrb_state, "Particles")
	ruby_obj := mrb.obj_new(g.mrb_state, cls, 0, nil)
	mrb.data_init(ruby_obj, pptr, NATIVE_TO_MRUBY_TYPE[Particles_Instance])
	pptr.ruby_obj = ruby_obj

	mrb.gc_register(g.mrb_state, ruby_obj)
	append(&particles_list, pptr)

	return ruby_obj
}

@(private = "file")
particles_spawn_one :: proc(p: ^Particles_Instance) {
	i := p.head
	was_alive := p.life[i] > 0
	life := sample_f(p.lifetime, 1)
	p.pos[i] = sample_v2(p.pos_spec, {0, 0})
	p.vel[i] = sample_v2(p.vel_spec, {0, 0})
	p.accel[i] = sample_v2(p.accel_spec, {0, 0})
	p.rot[i] = sample_f(p.rot_spec, 0)
	p.ang_vel[i] = sample_f(p.ang_vel_spec, 0)
	p.ang_accel[i] = sample_f(p.ang_accel_spec, 0)
	p.life[i] = life
	p.max_life[i] = life
	p.head = (p.head + 1) % p.max
	if !was_alive { p.count += 1 }
}

update_particles :: proc() {
	if len(particles_list) == 0 { return }

	for p in particles_list {
		if p.destroyed { continue }
		if p.running && p.rate > 0 {
			p.accum += FIXED_DT * p.rate
			for p.accum >= 1 {
				particles_spawn_one(p)
				p.accum -= 1
			}
		}
		has_drag := p.drag_spec.spec != nil
		has_ang_drag := p.ang_drag_spec.spec != nil
		_, has_accel_curve := p.accel_spec.spec.(Curve)
		_, has_ang_accel_curve := p.ang_accel_spec.spec.(Curve)
		for i in 0 ..< p.max {
			if p.life[i] <= 0 { continue }
			p.life[i] -= FIXED_DT
			if p.life[i] <= 0 {
				p.count -= 1
				continue
			}
			t := 1 - p.life[i] / p.max_life[i]
			acc := p.accel[i]
			if has_accel_curve { acc = eval_v2(p.accel_spec, t, {0, 0}) }
			p.vel[i] += acc * FIXED_DT
			if has_drag {
				d := clamp(eval_f(p.drag_spec, t, 0), 0, 1)
				p.vel[i] *= 1 - d
			}
			p.pos[i] += p.vel[i] * FIXED_DT

			ang_acc := p.ang_accel[i]
			if has_ang_accel_curve { ang_acc = eval_f(p.ang_accel_spec, t, 0) }
			p.ang_vel[i] += ang_acc * FIXED_DT
			if has_ang_drag {
				d := clamp(eval_f(p.ang_drag_spec, t, 0), 0, 1)
				p.ang_vel[i] *= 1 - d
			}
			p.rot[i] += p.ang_vel[i] * FIXED_DT
		}
	}

	// sweep destroyed
	w := 0
	for i in 0 ..< len(particles_list) {
		p := particles_list[i]
		if p.destroyed {
			if p.ruby_obj != mrb.NIL {
				mrb.gc_unregister(g.mrb_state, p.ruby_obj)
			}
			particles_unregister_refs(g.mrb_state, p)
			particles_free_storage(p)
		} else {
			particles_list[w] = p
			w += 1
		}
	}
	resize(&particles_list, w)
}

ruby_particles_draw :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.NIL }

	switch p.shape {
	case .Pixel:
		for i in 0 ..< p.max {
			if p.life[i] <= 0 { continue }
			t := 1 - p.life[i] / p.max_life[i]
			c := eval_color(p.color_spec, t, rl.WHITE)
			rl.DrawRectanglePro({p.pos[i].x, p.pos[i].y, 1, 1}, {0, 0}, 0, c)
		}
	case .Rect:
		for i in 0 ..< p.max {
			if p.life[i] <= 0 { continue }
			t := 1 - p.life[i] / p.max_life[i]
			s := eval_size(p.size_spec, t, {1, 1})
			c := eval_color(p.color_spec, t, rl.WHITE)
			rl.DrawRectanglePro({p.pos[i].x, p.pos[i].y, s.x, s.y}, s * 0.5, p.rot[i] * RAD_TO_DEG, c)
		}
	case .Circle:
		for i in 0 ..< p.max {
			if p.life[i] <= 0 { continue }
			t := 1 - p.life[i] / p.max_life[i]
			s := eval_size(p.size_spec, t, {1, 1})
			c := eval_color(p.color_spec, t, rl.WHITE)
			rl.DrawCircleSector(p.pos[i], s.x, 0, 360, 12, c)
		}
	case .Line:
		for i in 0 ..< p.max {
			if p.life[i] <= 0 { continue }
			t := 1 - p.life[i] / p.max_life[i]
			delta := eval_size(p.size_spec, t, {1, 1})
			c := eval_color(p.color_spec, t, rl.WHITE)
			length := math.sqrt(delta.x * delta.x + delta.y * delta.y)
			if length > 0 {
				angle_deg := (math.atan2(delta.y, delta.x) + p.rot[i]) * RAD_TO_DEG
				rl.DrawTexturePro(
					atlas_texture,
					atlas_white_uv,
					{p.pos[i].x, p.pos[i].y, length, 1},
					{0, 0.5},
					angle_deg,
					c,
				)
			}
		}
	}
	return self
}

ruby_particles_burst :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.NIL }
	n: i32
	mrb.get_args(state, "i", &n)
	for _ in 0 ..< n { particles_spawn_one(p) }
	return self
}

ruby_particles_start :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p != nil { p.running = true }
	return self
}

ruby_particles_stop :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p != nil { p.running = false }
	return self
}

ruby_particles_running :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.FALSE }
	return p.running ? mrb.TRUE : mrb.FALSE
}

ruby_particles_count :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.boxing_int_value(state, 0) }
	return mrb.boxing_int_value(state, p.count)
}

ruby_particles_max :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.boxing_int_value(state, 0) }
	return mrb.boxing_int_value(state, p.max)
}

ruby_particles_set_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.NIL }
	v: mrb.Value
	mrb.get_args(state, "o", &v)
	// release old ref
	if p.pos_spec.ref != mrb.NIL { mrb.gc_unregister(g.mrb_state, p.pos_spec.ref) }
	p.pos_spec = parse_prop(v, allow_shapes = true)
	return v
}

ruby_particles_get_pos :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p == nil { return mrb.NIL }
	if p.pos_spec.ref != mrb.NIL { return p.pos_spec.ref }
	// scalar v2 spec — re-wrap into ruby v2
	if v, ok := p.pos_spec.spec.(rl.Vector2); ok {
		return create_vector2(v)
	}
	return mrb.NIL
}

ruby_particles_destroy :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	p := extract_native(Particles_Instance, self)
	if p != nil { p.destroyed = true }
	return mrb.NIL
}

setup_particles :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Particles")
	mrb.define_method(g.mrb_state, c, "draw", cast(rawptr)ruby_particles_draw, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "burst", cast(rawptr)ruby_particles_burst, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "start", cast(rawptr)ruby_particles_start, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "stop", cast(rawptr)ruby_particles_stop, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "running?", cast(rawptr)ruby_particles_running, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "count", cast(rawptr)ruby_particles_count, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "max", cast(rawptr)ruby_particles_max, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "pos", cast(rawptr)ruby_particles_get_pos, mrb.ARGS_NONE)
	mrb.define_method(g.mrb_state, c, "pos=", cast(rawptr)ruby_particles_set_pos, mrb.ARGS_REQ(1))
	mrb.define_method(g.mrb_state, c, "destroy", cast(rawptr)ruby_particles_destroy, mrb.ARGS_NONE)
}

cleanup_particles :: proc() {
	// `Particles_Instance`s will be cleaned up by mruby shutdown
	delete(particles_list)
}
