package engine

import "base:runtime"
import "core:math/ease"
import mrb "lib:mruby"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

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
	debug:             bool,
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
	has_init:          bool,
	has_event:         bool,
	has_update:        bool,
	wants_dt:          bool,
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
	align, atlas, body, clip, color:         mrb.Value,
	default, delay, density, direction:      mrb.Value,
	easing, enter, exit:                     mrb.Value,
	fade_in, fade_out, filled, fliph, flipv: mrb.Value,
	font, frame, frames, friction:           mrb.Value,
	interval, layer, leading, loop, mask:    mrb.Value,
	mode, offset, outline:                   mrb.Value,
	pitch, polyphony, pos:                   mrb.Value,
	restitution, rotation, rounded:          mrb.Value,
	scale, sensor, size, slide, spacing:     mrb.Value,
	states, target, thickness, update:       mrb.Value,
	values, visible, volume, wrap, zoom:     mrb.Value,
}

cache_symbols :: proc() {
	s := g.mrb_state
	sv :: mrb.symbol_value
	intern :: mrb.intern_cstr
	sym = {
		align       = sv(intern(s, "align")),
		atlas       = sv(intern(s, "atlas")),
		body        = sv(intern(s, "body")),
		clip        = sv(intern(s, "clip")),
		color       = sv(intern(s, "color")),
		default     = sv(intern(s, "default")),
		delay       = sv(intern(s, "delay")),
		density     = sv(intern(s, "density")),
		direction   = sv(intern(s, "direction")),
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
		interval    = sv(intern(s, "interval")),
		layer       = sv(intern(s, "layer")),
		leading     = sv(intern(s, "leading")),
		loop        = sv(intern(s, "loop")),
		mask        = sv(intern(s, "mask")),
		mode        = sv(intern(s, "mode")),
		offset      = sv(intern(s, "offset")),
		outline     = sv(intern(s, "outline")),
		pitch       = sv(intern(s, "pitch")),
		polyphony   = sv(intern(s, "polyphony")),
		pos         = sv(intern(s, "pos")),
		restitution = sv(intern(s, "restitution")),
		rotation    = sv(intern(s, "rotation")),
		rounded     = sv(intern(s, "rounded")),
		scale       = sv(intern(s, "scale")),
		sensor      = sv(intern(s, "sensor")),
		size        = sv(intern(s, "size")),
		slide       = sv(intern(s, "slide")),
		spacing     = sv(intern(s, "spacing")),
		states      = sv(intern(s, "states")),
		target      = sv(intern(s, "target")),
		thickness   = sv(intern(s, "thickness")),
		update      = sv(intern(s, "update")),
		values      = sv(intern(s, "values")),
		visible     = sv(intern(s, "visible")),
		volume      = sv(intern(s, "volume")),
		wrap        = sv(intern(s, "wrap")),
		zoom        = sv(intern(s, "zoom")),
	}
}

global_context: runtime.Context
NATIVE_TO_MRUBY_TYPE: map[typeid]^mrb.Data_Type
g: ^Engine_Memory
