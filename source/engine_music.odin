package engine

import "core:c"
import "core:log"
import "core:path/slashpath"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

Music_Load_Status :: enum {
	PENDING,
	LOADED,
	UNLOADED,
}

Music :: struct {
	path:        string,
	file_data:   []u8, // stored because raylib streams from this buffer
	music:       rl.Music,
	active:      bool,
	autoplay:    bool,
	volume:      f32,
	looping:     bool,
	fade_time:   f32, // remaining fade time (0 = no fade)
	fade_target: f32, // target volume for fade
	fade_speed:  f32, // volume change per second during fade
	status:      Music_Load_Status,
}

ruby_music_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context
	if ptr != nil {
		music_ptr := cast(^Music)ptr

		// unload music stream
		rl.UnloadMusicStream(music_ptr.music)

		// free file data (raylib streams from this buffer)
		if music_ptr.file_data != nil {
			delete(music_ptr.file_data)
		}

		// free path string
		delete(music_ptr.path)

		// remove from global list
		for m, i in g.music {
			if m == music_ptr {
				ordered_remove(&g.music, i)
				break
			}
		}

		mrb.free(state, ptr)
	}
}

// helper to create Music DATA objects
create_music :: proc(path: string) -> mrb.Value {
	music_ptr := mrb.alloc(
		g.mrb_state,
		Music{path = strings.clone(path), active = false, volume = 1.0, looping = true},
	)

	// add to global list for updates
	append(&g.music, music_ptr)

	if g.audio_initialized {
		// load immediately if audio is ready
		load_music_data(music_ptr)
	} else {
		// defer loading until audio is initialized
		music_ptr.status = .PENDING
	}

	// create Ruby object
	music_class := mrb.class_get(g.mrb_state, "Music")
	ruby_obj := mrb.obj_new(g.mrb_state, music_class, 0, nil)

	// set @path instance variable
	path_sym := mrb.intern_cstr(g.mrb_state, "@path")
	path_val := mrb.str_new_cstr(g.mrb_state, strings.clone_to_cstring(path, context.temp_allocator))
	mrb.iv_set(g.mrb_state, ruby_obj, path_sym, path_val)

	mrb.data_init(ruby_obj, music_ptr, NATIVE_TO_MRUBY_TYPE[Music])

	return ruby_obj
}

// load actual music data (called when audio is initialized)
load_music_data :: proc(music: ^Music) {
	if music.status == .LOADED { return }

	// read file data into memory - we must keep this buffer alive because
	// raylib streams from it (unlike sounds which copy the data)
	file_data, ok := read_entire_file(music.path)
	if !ok {
		log.warnf("Unable to read music file: %s", music.path)
		music.status = .UNLOADED
		return
	}

	file_ext_cstr := strings.clone_to_cstring(slashpath.ext(music.path), context.temp_allocator)
	music_stream := rl.LoadMusicStreamFromMemory(file_ext_cstr, raw_data(file_data), c.int(len(file_data)))

	if music_stream.frameCount == 0 {
		music.status = .UNLOADED
		log.warnf("Warning: Unable to load music: %s", music.path)
		delete(file_data) // cleanup on failure
		return
	}

	// store file_data so it can be freed in finalizer
	music.file_data = file_data

	music.music = music_stream
	music.status = .LOADED
}

// load all deferred music (called when audio is initialized)
load_deferred_music :: proc() {
	for music in g.music {
		if music.status != .PENDING { continue }
		load_music_data(music)
		if music.autoplay { music_play(music) }
	}
}

// RUBY FUNCTION: music(path) -> returns Music object
// @engine_method: name="music", arity=1
ruby_music :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	path_val: mrb.Value
	mrb.get_args(state, "o", &path_val)

	// convert path to string
	str_obj := mrb.obj_as_string(state, path_val)
	c_str := mrb.str_to_cstr(state, str_obj)
	path := string(c_str)

	return create_music(path)
}

// RUBY METHOD: music.play(volume: 1.0, loop: true, fade_in: 0.0) -> plays music
ruby_music_play :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	// check if audio is initialized before playing (important for web builds)
	if !g.audio_initialized {
		return self // return self but don't actually play
	}

	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	music := extract_native(Music, self)
	if music == nil { return mrb.NIL }

	if argc == 1 {
		val: mrb.Value
		val = mrb.kwarg(state, kwargs, g.sym.volume)
		if val != mrb.NIL { music.volume = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, g.sym.fade_in)
		if val != mrb.NIL { music.fade_time = f32(mrb.to_f64(val)) }
		val = mrb.kwarg(state, kwargs, g.sym.loop)
		if val != mrb.NIL { music.looping = mrb.boolean(val) }
	}

	music_play(music)

	return self
}

music_play :: proc(music: ^Music) {
	// stop if already playing
	if rl.IsMusicStreamPlaying(music.music) {
		rl.StopMusicStream(music.music)
	}

	music.active = true
	music.music.looping = music.looping

	if music.fade_time > 0 {
		// start silent and fade in
		// use 1.0 as default target if volume is 0 (from previous fade out)
		target_volume := music.volume if music.volume > 0 else 1.0
		music.fade_target = target_volume
		music.fade_speed = target_volume / music.fade_time
		music.volume = 0.0
	} else {
		// if no fade and volume is 0 (from previous fade out), reset to 1.0
		if music.volume == 0 {
			music.volume = 1.0
		}
	}

	rl.SetMusicVolume(music.music, music.volume)
	rl.PlayMusicStream(music.music)
}

ruby_music_autoplay :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	music := extract_native(Music, self)
	if music == nil { return mrb.NIL }

	music.autoplay = true
	if g.audio_initialized { music_play(music) }

	return self
}

// RUBY METHOD: music.stop(fade_out: 0.0) -> stops music
ruby_music_stop :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	music := extract_native(Music, self)
	if music == nil { return mrb.NIL }

	fade_time := f32(0.0)

	if argc == 1 {
		val := mrb.kwarg(state, kwargs, g.sym.fade_out)
		if val != mrb.NIL { fade_time = f32(mrb.to_f64(val)) }
	}

	if music.active && rl.IsMusicStreamPlaying(music.music) {
		if fade_time > 0 {
			// start fade out
			music.fade_time = fade_time
			music.fade_target = 0.0
			music.fade_speed = music.volume / fade_time
		} else {
			// stop immediately
			rl.StopMusicStream(music.music)
			music.active = false
		}
	}

	return self
}

// RUBY METHOD: music.pause(fade_out: 0.0) -> pauses music
ruby_music_pause :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	kwargs: mrb.Value
	argc := mrb.get_args(state, "|H", &kwargs)

	music := extract_native(Music, self)
	if music == nil { return mrb.NIL }

	fade_time := f32(0.0)

	if argc == 1 {
		val := mrb.kwarg(state, kwargs, g.sym.fade_out)
		if val != mrb.NIL { fade_time = f32(mrb.to_f64(val)) }
	}

	if music.active && rl.IsMusicStreamPlaying(music.music) {
		if fade_time > 0 {
			// start fade out to pause
			music.fade_time = fade_time
			music.fade_target = 0.0
			music.fade_speed = music.volume / fade_time
		} else {
			// pause immediately
			rl.PauseMusicStream(music.music)
		}
	}

	return self
}

// RUBY METHOD: music.active -> returns boolean
ruby_music_active :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	music := extract_native(Music, self)
	if music == nil { return mrb.FALSE }
	return music.active ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: music.looping -> returns boolean
ruby_music_looping :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	music := extract_native(Music, self)
	if music == nil { return mrb.FALSE }
	return music.looping ? mrb.TRUE : mrb.FALSE
}

// RUBY METHOD: music.volume -> returns float
ruby_music_volume :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	music := extract_native(Music, self)
	if music == nil { return mrb.word_boxing_float_value(state, 0.0) }
	return mrb.word_boxing_float_value(state, f64(music.volume))
}

// RUBY METHOD: music.volume= -> sets volume
ruby_music_set_volume :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	volume_val: mrb.Value
	mrb.get_args(state, "o", &volume_val)

	music := extract_native(Music, self)
	if music == nil { return volume_val }

	new_volume := f32(mrb.to_f64(volume_val))
	music.volume = new_volume

	// update Raylib volume if music is active
	if music.active { rl.SetMusicVolume(music.music, new_volume) }

	return volume_val
}

// RUBY METHOD: music.fade_time -> returns float (for debugging)
ruby_music_fade_time :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	music := extract_native(Music, self)
	if music == nil { return mrb.word_boxing_float_value(state, 0.0) }
	return mrb.word_boxing_float_value(state, f64(music.fade_time))
}

// music system update - handles streaming, fades and cleanup
update_music_system :: proc(dt: f32) {
	for music in g.music {
		if !music.active { continue }

		// update music stream (to keep it playing)
		rl.UpdateMusicStream(music.music)

		// handle fading
		if music.fade_time > 0 {
			result, new_fade_time, new_volume := apply_fade(
				music.fade_time, music.fade_target, music.fade_speed, music.volume, dt,
			)
			music.fade_time = new_fade_time
			music.volume = new_volume
			rl.SetMusicVolume(music.music, music.volume)

			if result == .STOPPED {
				rl.StopMusicStream(music.music)
				music.active = false
			}
		}

		// check if music finished playing naturally
		if !rl.IsMusicStreamPlaying(music.music) && !music.looping {
			// non-looping music finished - just mark inactive, keep loaded
			music.active = false
		}
	}
}

setup_music :: proc() {
	mus := mrb.get_data_class(g.mrb_state, "Music")
	mrb.define_method(g.mrb_state, mus, "play", cast(rawptr)ruby_music_play, -1)
	mrb.define_method(g.mrb_state, mus, "stop", cast(rawptr)ruby_music_stop, -1)
	mrb.define_method(g.mrb_state, mus, "pause", cast(rawptr)ruby_music_pause, -1)
	mrb.define_method(g.mrb_state, mus, "autoplay", cast(rawptr)ruby_music_autoplay, 0)
	mrb.define_method(g.mrb_state, mus, "playing?", cast(rawptr)ruby_music_active, 0)
	mrb.define_method(g.mrb_state, mus, "looping?", cast(rawptr)ruby_music_looping, 0)
	mrb.define_method(g.mrb_state, mus, "volume", cast(rawptr)ruby_music_volume, 0)
	mrb.define_method(g.mrb_state, mus, "volume=", cast(rawptr)ruby_music_set_volume, 1)
	mrb.define_method(g.mrb_state, mus, "fade_time", cast(rawptr)ruby_music_fade_time, 0)
}
