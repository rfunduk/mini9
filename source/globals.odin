package engine

import "base:runtime"
import "core:math/ease"
import mrb "lib:mruby"
import rl "lib:raylib"
import rlgl "lib:raylib/rlgl"

// Compile-time flag: this is a debug build of mini9 itself (the framework),
// not a debug build of a game made with it. Toggles framework-dev affordances
// like SAFE_DISPATCH, default log verbosity, etc.
ENGINE_DEBUG :: #config(ENGINE_DEBUG, false)

// 16.67ms fixed timestep
FIXED_DT: f32 = 1.0 / 60.0

// cap at 250ms (prevents spiral of death)
MAX_FRAME_TIME: f32 = 0.25

Game_Phase :: enum {
	INIT,
	UPDATE,
	DRAW,
	FLUX,
}

Engine_Memory :: struct {
	rom_data:          ^Rom_Data,
	rom_path:          string,
	title:             string,
	resolution:        rl.Vector2,
	metrics:           bool,
	fps:               i32,
	camera:            rl.Camera2D,
	render_texture:    rl.RenderTexture2D,
	clear_color:       rl.Color,
	flux:              ease.Flux_Map(f32),
	run:               bool,
	phase:             Game_Phase,
	cursor:            bool,
	audio_initialized: bool,
	dest_rect:         rl.Rectangle,
	batch:             rlgl.RenderBatch,
	draw_calls:        i32,
	has_update:        bool,
	has_draw:          bool,
	has_ui:            bool,
	frame_count:       u32,

	// mruby vm
	mrb_state:         mrb.State,
	mrb_ctx:           mrb.CContext,

	// game-visible engine state
	cameras:           [dynamic]^Camera_Instance,
	sounds:            [dynamic]^Sound,
	music:             [dynamic]^Music,
	shake_instances:   [dynamic]^Shake_Instance,

	// built-in fonts
	fonts:             struct {
		tiny:   rl.Font, // 5px - Font::TINY
		small:  rl.Font, // 8px - Font::SMALL
		medium: rl.Font, // 11px - Font::MEDIUM
		large:  rl.Font, // 15px - Font::LARGE
	},
}

sym: struct {
	accel, align, ang_accel, ang_drag, ang_vel: mrb.Value,
	atlas, body, bounds, circle, clip, color:   mrb.Value,
	default, delay, density, direction, drag:   mrb.Value,
	easing, enter, exit:                        mrb.Value,
	fade_in, fade_out, filled, fliph, flipv:    mrb.Value,
	font, frame, frames, friction:              mrb.Value,
	holes, interval, layer, leading, lifetime:  mrb.Value,
	limit, line, loop, margin, mask, max:       mrb.Value,
	mode, offset, origin, outline:              mrb.Value,
	pitch, pixel, polyphony, pos:               mrb.Value,
	rate, rect, restitution, rotation, rounded: mrb.Value,
	scale, sensor, shape, size, slide:          mrb.Value,
	spacing, start, states:                     mrb.Value,
	target, thickness, update:                  mrb.Value,
	values, velocity, visible, volume:          mrb.Value,
	wrap, zoom:                                 mrb.Value,
}

cache_symbols :: proc() {
	s := g.mrb_state
	sv :: mrb.symbol_value
	intern :: mrb.intern_cstr
	sym = {
		accel       = sv(intern(s, "accel")),
		align       = sv(intern(s, "align")),
		ang_accel   = sv(intern(s, "ang_accel")),
		ang_drag    = sv(intern(s, "ang_drag")),
		ang_vel     = sv(intern(s, "ang_vel")),
		atlas       = sv(intern(s, "atlas")),
		body        = sv(intern(s, "body")),
		bounds      = sv(intern(s, "bounds")),
		circle      = sv(intern(s, "circle")),
		clip        = sv(intern(s, "clip")),
		color       = sv(intern(s, "color")),
		default     = sv(intern(s, "default")),
		delay       = sv(intern(s, "delay")),
		density     = sv(intern(s, "density")),
		direction   = sv(intern(s, "direction")),
		drag        = sv(intern(s, "drag")),
		easing      = sv(intern(s, "easing")),
		enter       = sv(intern(s, "enter")),
		exit        = sv(intern(s, "exit")),
		fade_in     = sv(intern(s, "fade_in")),
		fade_out    = sv(intern(s, "fade_out")),
		filled      = sv(intern(s, "filled")),
		fliph       = sv(intern(s, "fliph")),
		flipv       = sv(intern(s, "flipv")),
		font        = sv(intern(s, "font")),
		frame       = sv(intern(s, "frame")),
		frames      = sv(intern(s, "frames")),
		friction    = sv(intern(s, "friction")),
		holes       = sv(intern(s, "holes")),
		interval    = sv(intern(s, "interval")),
		layer       = sv(intern(s, "layer")),
		leading     = sv(intern(s, "leading")),
		lifetime    = sv(intern(s, "lifetime")),
		limit       = sv(intern(s, "limit")),
		line        = sv(intern(s, "line")),
		loop        = sv(intern(s, "loop")),
		margin      = sv(intern(s, "margin")),
		mask        = sv(intern(s, "mask")),
		max         = sv(intern(s, "max")),
		mode        = sv(intern(s, "mode")),
		offset      = sv(intern(s, "offset")),
		origin      = sv(intern(s, "origin")),
		outline     = sv(intern(s, "outline")),
		pitch       = sv(intern(s, "pitch")),
		pixel       = sv(intern(s, "pixel")),
		polyphony   = sv(intern(s, "polyphony")),
		pos         = sv(intern(s, "pos")),
		rate        = sv(intern(s, "rate")),
		rect        = sv(intern(s, "rect")),
		restitution = sv(intern(s, "restitution")),
		rotation    = sv(intern(s, "rotation")),
		rounded     = sv(intern(s, "rounded")),
		scale       = sv(intern(s, "scale")),
		sensor      = sv(intern(s, "sensor")),
		shape       = sv(intern(s, "shape")),
		size        = sv(intern(s, "size")),
		slide       = sv(intern(s, "slide")),
		spacing     = sv(intern(s, "spacing")),
		start       = sv(intern(s, "start")),
		states      = sv(intern(s, "states")),
		target      = sv(intern(s, "target")),
		thickness   = sv(intern(s, "thickness")),
		update      = sv(intern(s, "update")),
		values      = sv(intern(s, "values")),
		velocity    = sv(intern(s, "velocity")),
		visible     = sv(intern(s, "visible")),
		volume      = sv(intern(s, "volume")),
		wrap        = sv(intern(s, "wrap")),
		zoom        = sv(intern(s, "zoom")),
	}
}

global_context: runtime.Context
NATIVE_TO_MRUBY_TYPE: map[typeid]^mrb.Data_Type
g: ^Engine_Memory
