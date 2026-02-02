package engine

import "core:log"
import "core:path/filepath"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

Sound_Load_Status :: enum {
	PENDING,
	LOADED,
	UNLOADED,
}

// sound instance for polyphony support
Sound_Instance :: struct {
	sound:       rl.Sound,
	active:      bool,
	volume:      f32,
	pitch:       f32,
	fade_time:   f32, // remaining fade time (0 = no fade)
	fade_target: f32, // target volume for fade
	fade_speed:  f32, // volume change per second during fade
	play_time:   f32, // time when this instance was last played
}

// main sound object with instance pool
Sound :: struct {
	path:      string,
	master:    rl.Sound, // master sound that owns the data
	instances: [dynamic]Sound_Instance,
	max_poly:  int,
	status:    Sound_Load_Status,
}

// Fade_Result indicates what happened during fade processing
Fade_Result :: enum {
	FADING,         // still fading
	COMPLETED,      // fade finished, target reached
	STOPPED,        // fade finished with target 0 (should stop playback)
}

// apply_fade processes a single frame of fade logic, returning the result and new volume
// Call this once per frame for any audio source that supports fading
apply_fade :: proc(fade_time, fade_target, fade_speed, volume, dt: f32) -> (result: Fade_Result, new_fade_time, new_volume: f32) {
	new_fade_time = fade_time - dt
	new_volume = volume

	if new_fade_time <= 0 {
		// fade complete
		new_fade_time = 0
		new_volume = fade_target
		if fade_target == 0 {
			return .STOPPED, new_fade_time, new_volume
		}
		return .COMPLETED, new_fade_time, new_volume
	}

	// continue fading - adjust volume based on direction
	if fade_target > volume {
		// fading in (up)
		new_volume = min(volume + fade_speed * dt, fade_target)
	} else {
		// fading out (down)
		new_volume = max(volume - fade_speed * dt, fade_target)
	}

	return .FADING, new_fade_time, new_volume
}

ruby_sound_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		sound_ptr := cast(^Sound)ptr

		// unload all aliases
		for &instance in sound_ptr.instances {
			rl.UnloadSoundAlias(instance.sound)
		}
		delete(sound_ptr.instances)

		// unload master
		rl.UnloadSound(sound_ptr.master)

		// free path string
		delete(sound_ptr.path)

		// remove from global list
		for i in 0 ..< len(g.sounds) {
			if g.sounds[i] == sound_ptr {
				ordered_remove(&g.sounds, i)
				break
			}
		}

		mrb.free(state, ptr)
	}
}

create_sound :: proc(path: string, polyphony: int = 8) -> mrb.Value {
	sound_ptr := ruby_allocate(
		Sound,
		Sound {
			path = strings.clone(path),
			max_poly = polyphony,
			instances = make([dynamic]Sound_Instance, 0, polyphony),
		},
	)

	// add to global list for updates
	append(&g.sounds, sound_ptr)

	if g.audio_initialized {
		// load immediately if audio is ready
		load_sound_data(sound_ptr)
	} else {
		// defer loading until audio is initialized
		sound_ptr.status = .PENDING
	}

	// create Ruby object
	sound_class := mrb.class_get(g.mrb_state, "Sound")
	ruby_obj := mrb.obj_new(g.mrb_state, sound_class, 0, nil)

	// set @path instance variable
	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	mrb.data_init(ruby_obj, sound_ptr, NATIVE_TO_MRUBY_TYPE[Sound])

	return ruby_obj
}

// load actual sound data (called when audio is initialized)
load_sound_data :: proc(sound: ^Sound) {
	if sound.status == .LOADED { return }

	// read file data into memory first
	file_data, ok := read_entire_file(sound.path)
	if !ok {
		log.warnf("Unable to read sound file: %s", sound.path)
		sound.status = .UNLOADED
		return
	}
	defer delete(file_data)

	// get file extension for LoadWaveFromMemory
	file_ext_cstr := strings.clone_to_cstring(filepath.ext(sound.path), context.temp_allocator)

	// load wave from memory data
	wave := rl.LoadWaveFromMemory(file_ext_cstr, raw_data(file_data), i32(len(file_data)))
	defer rl.UnloadWave(wave)

	// convert wave to sound
	master_sound := rl.LoadSoundFromWave(wave)

	if master_sound.frameCount == 0 {
		log.warnf("Unable to load sound: %s", sound.path)
		sound.status = .UNLOADED
		return
	}

	sound.master = master_sound
	sound.status = .LOADED

	// create instance pool using aliases
	for _ in 0 ..< sound.max_poly {
		instance := Sound_Instance {
			sound  = rl.LoadSoundAlias(master_sound),
			active = false,
			volume = 1.0,
			pitch  = 1.0,
		}
		append(&sound.instances, instance)
	}
}

// load all deferred sounds (called when audio is initialized)
load_deferred_sounds :: proc() {
	for sound in g.sounds { load_sound_data(sound) }
}

// find an inactive instance to use for playback
find_free_instance :: proc(sound: ^Sound) -> ^Sound_Instance {
	// first, look for truly inactive instances
	for &instance in sound.instances {
		if !instance.active && !rl.IsSoundPlaying(instance.sound) {
			return &instance
		}
	}

	// if all are active, find the oldest one and reuse it
	if len(sound.instances) > 0 {
		oldest_idx := 0
		oldest_time := sound.instances[0].play_time

		for i in 1 ..< len(sound.instances) {
			if sound.instances[i].play_time < oldest_time {
				oldest_idx = i
				oldest_time = sound.instances[i].play_time
			}
		}

		oldest := &sound.instances[oldest_idx]
		rl.StopSound(oldest.sound)
		oldest.active = false
		return oldest
	}

	return nil
}

// RUBY FUNCTION: sound(path, polyphony: 8) -> returns Sound object
// @engine_method: name="sound", arity=1
ruby_sound :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val, kwargs: mrb.Value
	argc := mrb.get_args(state, "o|H", &path_val, &kwargs)

	// convert path to string
	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := string(c_str)

	polyphony := 8 // default polyphony

	if argc == 2 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)
		if "polyphony" in hash {
			polyphony = int(mrb.integer(hash["polyphony"]))
		}
	}

	result := create_sound(path, polyphony)
	return result
}

// RUBY METHOD: sound.play(pitch: 1.0, volume: 1.0) -> plays sound instance
ruby_sound_play :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	// check if audio is initialized before playing (important for web builds)
	if !g.audio_initialized { return self } 	// return self but don't actually play

	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	sound := extract_native(Sound, self)
	if sound == nil { return mrb.NIL }

	// ensure sound is loaded before playing
	if sound.status != .LOADED {
		if g.audio_initialized {
			load_sound_data(sound)
		}
		if sound.status != .LOADED {
			return self // sound not ready, return silently
		}
	}

	instance := find_free_instance(sound)
	if instance == nil { return mrb.NIL }

	// set default values
	pitch := f32(1.0)
	volume := f32(1.0)

	// parse kwargs
	if argc == 1 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)
		if "pitch" in hash { pitch = f32(to_f64(hash["pitch"])) }
		if "volume" in hash { volume = f32(to_f64(hash["volume"])) }
	}

	// configure instance
	instance.pitch = pitch
	instance.volume = volume
	instance.fade_time = 0
	instance.active = true
	instance.play_time = f32(rl.GetTime())

	rl.SetSoundPitch(instance.sound, pitch)
	rl.SetSoundVolume(instance.sound, volume)
	rl.PlaySound(instance.sound)

	return self
}

// RUBY METHOD: sound.stop(fade_out: 0.0) -> stops all instances
ruby_sound_stop :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	sound := extract_native(Sound, self)
	if sound == nil { return mrb.NIL }

	fade_time := f32(0.0)

	if argc == 1 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)
		if "fade_out" in hash { fade_time = f32(to_f64(hash["fade_out"])) }
	}

	for &instance in sound.instances {
		if instance.active && rl.IsSoundPlaying(instance.sound) {
			if fade_time > 0 {
				// start fade out
				instance.fade_time = fade_time
				instance.fade_target = 0.0
				instance.fade_speed = instance.volume / fade_time
			} else {
				// stop immediately
				rl.StopSound(instance.sound)
				instance.active = false
			}
		}
	}

	return self
}

// RUBY METHOD: sound.pause(fade_out: 0.0) -> pauses all instances
ruby_sound_pause :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	sound := extract_native(Sound, self)
	if sound == nil { return mrb.NIL }

	fade_time := f32(0.0)

	if argc == 1 && kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)
		if "fade_out" in hash { fade_time = f32(to_f64(hash["fade_out"])) }
	}

	for &instance in sound.instances {
		if instance.active && rl.IsSoundPlaying(instance.sound) {
			if fade_time > 0 {
				// start fade out to pause
				instance.fade_time = fade_time
				instance.fade_target = 0.0
				instance.fade_speed = instance.volume / fade_time
			} else {
				// pause immediately
				rl.PauseSound(instance.sound)
			}
		}
	}

	return self
}

// audio system update - handles fades and cleanup
update_audio_system :: proc(dt: f32) {
	for sound in g.sounds {
		for &instance in sound.instances {
			if !instance.active { continue }

			// handle fading
			if instance.fade_time > 0 {
				result, new_fade_time, new_volume := apply_fade(
					instance.fade_time, instance.fade_target, instance.fade_speed, instance.volume, dt,
				)
				instance.fade_time = new_fade_time
				instance.volume = new_volume
				rl.SetSoundVolume(instance.sound, instance.volume)

				if result == .STOPPED {
					rl.StopSound(instance.sound)
					instance.active = false
				}
			}

			// check if sound finished playing naturally
			if !rl.IsSoundPlaying(instance.sound) {
				instance.active = false
			}
		}
	}
}

setup_sound :: proc() {
	snd := create_data_class("Sound")
	mrb.define_method(g.mrb_state, snd, "play", cast(rawptr)ruby_sound_play, -1)
	mrb.define_method(g.mrb_state, snd, "stop", cast(rawptr)ruby_sound_stop, -1)
	mrb.define_method(g.mrb_state, snd, "pause", cast(rawptr)ruby_sound_pause, -1)
}
