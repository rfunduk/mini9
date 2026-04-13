package engine

import "core:log"
import "core:math/ease"
import "core:time"
import mrb "lib:mruby"
import rl "vendor:raylib"

@(private = "file")
pending_tweens: [dynamic]^Tween_Instance

Tween_Type :: union {
	f32,
	rl.Vector2,
	rl.Color,
}

Tween_Instance :: struct {
	type:           typeid,
	ruby_obj:       mrb.Value, // a reference to the ruby object
	from:           mrb.Value,
	to:             mrb.Value,
	easing:         ease.Ease,
	value:          Tween_Type, // the thing being tweened
	finished_frame: u32, // tween finished this frame
	duration:       f64, // original duration of the tween
	delay:          f64, // delay before tween starts
	start_time:     time.Time, // when tween was created
	initialized:    bool, // marked true when flux calls on_start
	update_block:   mrb.Value, // ruby block/proc if provided
}

ruby_tween_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		tween := cast(^Tween_Instance)ptr
		tween_stop(tween)
		mrb.gc_unregister(state, tween.from)
		mrb.gc_unregister(state, tween.to)
		mrb.free(state, ptr)
	}
}

create_tween :: proc(value_type: typeid) -> mrb.Value {
	t := Tween_Instance {
		type           = value_type,
		finished_frame = 0, // 0 means never finished (impossible to finish on frame 0)
		easing         = .Linear,
		delay          = 0,
	}
	tween := mrb.alloc(g.mrb_state, t)

	// initialize union value based on runtime type
	switch value_type {
	case f32:
		tween.value = f32(0)
	case rl.Vector2:
		tween.value = rl.Vector2{}
	case rl.Color:
		tween.value = rl.Color{}
	}

	tween_class := mrb.class_get(g.mrb_state, "Tween")
	ruby_obj := mrb.obj_new(g.mrb_state, tween_class, 0, nil)
	mrb.data_init(ruby_obj, tween, NATIVE_TO_MRUBY_TYPE[Tween_Instance])

	return ruby_obj
}

detect_tween_type :: proc(value: mrb.Value) -> typeid {
	vec_ptr := mrb.data_check_get_ptr(g.mrb_state, value, NATIVE_TO_MRUBY_TYPE[rl.Vector2])
	if vec_ptr != nil { return rl.Vector2 }

	// Color tweens are not yet implemented; reject upfront so we never
	// construct a Tween_Instance whose setup path would later panic from
	// a non-dispatch context (e.g. start_pending_tweens between frames).
	color_ptr := mrb.data_check_get_ptr(g.mrb_state, value, NATIVE_TO_MRUBY_TYPE[rl.Color])
	if color_ptr != nil {
		mrb.raise_error(g.mrb_state, "NotImplementedError", "Color tweens are not yet supported")
		return f32 // unreachable: ruby_raise longjmps via mrb.raise
	}

	if mrb.integer_p(value) || mrb.float_p(value) { return f32 }

	mrb.raise_error(g.mrb_state, "TypeError", "Only Vector2 and numbers can be tweened")
	return f32 // unreachable: ruby_raise longjmps via mrb.raise
}

// RUBY FUNCTION: tween(from, to, duration, delay: 0, easing: Tween.LINEAR) { block } -> returns Tween object
// @engine_method: name="tween", arity=-1
ruby_tween :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	from_val, to_val, kwargs, block: mrb.Value
	duration: f64
	argc := mrb.get_args(state, "oof|H&", &from_val, &to_val, &duration, &kwargs, &block)

	if argc < 3 { return mrb.NIL }

	from_type := detect_tween_type(from_val)
	to_type := detect_tween_type(to_val)

	if from_type != to_type {
		return mrb.raise_error(state, "TypeError", "tween from/to must be the same type")
	}

	tween_obj := create_tween(from_type)
	tween := extract_native(Tween_Instance, tween_obj)
	if tween == nil { return mrb.NIL }

	if argc >= 4 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, sym.delay)
		if val != mrb.NIL { tween.delay = mrb.to_f64(val) }
		val = mrb.kwarg(state, kwargs, sym.easing)
		if val != mrb.NIL { tween.easing = ease.Ease(mrb.integer(val)) }
	}

	// we're going to hold onto these for the life of the tween
	mrb.gc_register(state, from_val)
	mrb.gc_register(state, to_val)

	tween.ruby_obj = tween_obj
	tween.from = from_val
	tween.to = to_val
	tween.duration = duration
	tween.start_time = time.now()

	// register the tween object with GC to prevent collection
	// it will be unregistered when completed
	mrb.gc_register(state, tween_obj)

	// store the block if provided
	if block != mrb.NIL && mrb.proc_p(block) {
		tween.update_block = block
		mrb.gc_register(state, tween.update_block)
	}

	start_or_queue_tween(tween)

	return tween_obj
}

start_or_queue_tween :: proc(tween: ^Tween_Instance) {
	context = global_context

	if g.phase == .FLUX {
		append(&pending_tweens, tween)
	} else {
		switch &v in tween.value {
		case rl.Vector2:
			from_vec := extract_native(rl.Vector2, tween.from)
			to_vec := extract_native(rl.Vector2, tween.to)
			v = rl.Vector2{from_vec.x, from_vec.y}
			start_tween(tween, &v.x, to_vec.x, true)
			start_tween(tween, &v.y, to_vec.y)
		case f32:
			from := mrb.to_f64(tween.from)
			to := mrb.to_f64(tween.to)
			v = f32(from)
			start_tween(tween, &v, f32(to), true)
		case rl.Color:
			// unreachable: detect_tween_type rejects Color upfront. If we
			// somehow got here we're outside any dispatch (called from
			// start_pending_tweens between frames), so log and skip rather
			// than longjmp via ruby_raise.
			log.error("internal: Color tween reached setup path despite type check; skipping")
		}
	}
}

start_pending_tweens :: proc() {
	for t in pending_tweens { start_or_queue_tween(t) }
	clear(&pending_tweens)
}

start_tween :: proc(tween: ^Tween_Instance, value_ptr: ^f32, goal: f32, primary: bool = false) {
	fluxing := ease.flux_to(
		flux = &g.flux,
		value = value_ptr,
		goal = goal,
		type = tween.easing,
		duration = time.Duration(tween.duration * f64(time.Second)),
		delay = tween.delay,
	)

	// only the 'primary' tween will get callbacks
	// because otherwise we'd trigger twice for vector2, 4 times for color, etc
	if primary {
		fluxing.on_start = tween_start_callback
		fluxing.on_complete = tween_completion_callback
		fluxing.on_update = tween_update_callback
	}

	fluxing.data = tween // pass tween instance to callback
}

tween_start_callback :: proc(flux: ^ease.Flux_Map(f32), data: rawptr) {
	tween := cast(^Tween_Instance)data
	if tween == nil { return }
	tween.initialized = true
}

tween_update_callback :: proc(flux: ^ease.Flux_Map(f32), data: rawptr) {
	tween := cast(^Tween_Instance)data
	g.phase = .FLUX
	defer { g.phase = .UPDATE }
	call_update_proc(tween)
}

call_update_proc :: proc(tween: ^Tween_Instance) {
	if tween == nil || tween.update_block == mrb.NIL { return }
	if !dispatch_yield(tween.update_block, tween.ruby_obj, .TWEEN_CALLBACK) {
		// callback raised — disable it so we don't keep replaying the same
		// error every frame (tween fires its callback on every flux tick).
		// the tween's value continues to update through completion; the
		// existing nil-check in tween_completion_callback handles teardown.
		log.warnf("tween update callback raised; disabling it for the rest of this tween")
		mrb.gc_unregister(g.mrb_state, tween.update_block)
		tween.update_block = mrb.NIL
	}
}

tween_completion_callback :: proc(flux: ^ease.Flux_Map(f32), data: rawptr) {
	tween := cast(^Tween_Instance)data
	if tween == nil { return }

	// set #just_finished? and call the update proc one last time
	tween.finished_frame = g.frame_count

	g.phase = .FLUX
	defer { g.phase = .UPDATE }
	call_update_proc(tween)

	// then clean up our objects
	// the key in the flux map will have already been deleted, tween will get gc'd
	if tween.update_block != mrb.NIL {
		mrb.gc_unregister(g.mrb_state, tween.update_block)
		tween.update_block = mrb.NIL
	}
	if tween.ruby_obj != mrb.NIL {
		mrb.gc_unregister(g.mrb_state, tween.ruby_obj)
		tween.ruby_obj = mrb.NIL
	}
}

ruby_tween_value :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	tween := extract_native(Tween_Instance, self)
	if tween == nil { return mrb.NIL }

	switch v in tween.value {
	case rl.Vector2:
		return create_vector2(v)
	case f32:
		return mrb.word_boxing_float_value(state, f64(v))
	case rl.Color:
		// unreachable: detect_tween_type rejects Color upfront, so no
		// Tween_Instance with rl.Color value can exist. Defensive raise
		// in case the type-check is ever bypassed.
		return mrb.raise_error(g.mrb_state, "NotImplementedError", "Color tweens are not yet supported")
	}

	return mrb.NIL
}

ruby_tween_running :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return tween_time_left(self) > 0 ? mrb.TRUE : mrb.FALSE
}

ruby_tween_finished :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return tween_time_left(self) <= 0 ? mrb.TRUE : mrb.FALSE
}

ruby_tween_just_finished :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	tween := extract_native(Tween_Instance, self)
	if tween == nil { return mrb.NIL }
	return tween.finished_frame == g.frame_count ? mrb.TRUE : mrb.FALSE
}

ruby_tween_time_left :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	return mrb.word_boxing_float_value(state, tween_time_left(self))
}

ruby_tween_progress :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	tween := extract_native(Tween_Instance, self)
	if tween == nil { return mrb.word_boxing_float_value(state, 1.0) }

	time_left := tween_time_left(self)
	elapsed := tween.duration - time_left
	progress := clamp(elapsed / tween.duration, 0.0, 1.0)

	return mrb.word_boxing_float_value(state, progress)
}

ruby_tween_stop :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	tween := extract_native(Tween_Instance, self)
	if tween != nil { tween_stop(tween) }
	return mrb.NIL
}

tween_stop :: proc(t: ^Tween_Instance) {
	// stop the flux tween(s) for this instance
	switch &v in t.value {
	case f32:
		_ = ease.flux_stop(&g.flux, &v)
	case rl.Vector2:
		_ = ease.flux_stop(&g.flux, &v.x) // x component
		_ = ease.flux_stop(&g.flux, &v.y) // y component
	case rl.Color:
		_ = ease.flux_stop(&g.flux, cast(^f32)&v[0]) // r component
		_ = ease.flux_stop(&g.flux, cast(^f32)&v[1]) // g component
		_ = ease.flux_stop(&g.flux, cast(^f32)&v[2]) // b component
		_ = ease.flux_stop(&g.flux, cast(^f32)&v[3]) // a component
	}
}

tween_time_left :: proc(self: mrb.Value) -> f64 {
	tween := extract_native(Tween_Instance, self)
	if tween == nil { return 0 }

	// calculate elapsed time since tween creation
	elapsed := time.duration_seconds(time.since(tween.start_time))
	total_time := tween.delay + tween.duration

	// if still in delay period, return delay remaining + full duration
	if elapsed < tween.delay { return total_time - elapsed }

	// if tween hasn't been initialized by flux yet but delay is over, something's wrong
	if !tween.initialized { return tween.duration }

	// during animation, get actual flux time remaining
	switch &v in tween.value {
	case f32:
		return ease.flux_tween_time_left(g.flux, &v)
	case rl.Vector2:
		x_time := ease.flux_tween_time_left(g.flux, &v.x)
		y_time := ease.flux_tween_time_left(g.flux, &v.y)
		return max(x_time, y_time)
	case rl.Color:
		return ease.flux_tween_time_left(g.flux, cast(^f32)&v[0])
	}

	return 0
}

setup_tween :: proc() {
	c := mrb.get_data_class(g.mrb_state, "Tween")

	mrb.define_method(g.mrb_state, c, "value", cast(rawptr)ruby_tween_value, 0)
	mrb.define_method(g.mrb_state, c, "running?", cast(rawptr)ruby_tween_running, 0)
	mrb.define_method(g.mrb_state, c, "finished?", cast(rawptr)ruby_tween_finished, 0)
	mrb.define_method(g.mrb_state, c, "just_finished?", cast(rawptr)ruby_tween_just_finished, 0)
	mrb.define_method(g.mrb_state, c, "time_left", cast(rawptr)ruby_tween_time_left, 0)
	mrb.define_method(g.mrb_state, c, "progress", cast(rawptr)ruby_tween_progress, 0)
	mrb.define_method(g.mrb_state, c, "stop", cast(rawptr)ruby_tween_stop, 0)
}

cleanup_tween :: proc() {
	delete(pending_tweens)
}
