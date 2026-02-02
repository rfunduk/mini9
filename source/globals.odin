package engine

import "base:runtime"
import "core:math/ease"
import mrb "lib:mruby"
import rl "vendor:raylib"

Game_Phase :: enum {
	INIT,
	UPDATE,
	DRAW,
	FLUX,
}

Engine_Memory :: struct {
	rom_data:             ^Rom_Data,
	title:                string,
	resolution:           rl.Vector2,
	debug:                bool,
	metrics:              bool,
	fps:                  i32,
	camera:               rl.Camera2D,
	render_texture:       rl.RenderTexture2D,
	clear_color:          rl.Color,
	flux:                 ease.Flux_Map(f32),
	run:                  bool,
	phase:                Game_Phase,
	cursor:               bool,
	audio_initialized:    bool,
	dest_rect:            rl.Rectangle,
	has_init:             bool,
	has_event:            bool,
	has_update:           bool,
	wants_dt:             bool,
	has_draw:             bool,
	has_ui:               bool,
	frame_count:          u32,

	// mruby vm
	mrb_state:            mrb.State,
	mrb_ctx:              mrb.CContext,

	// cameras
	cameras:              [dynamic]^Camera_Instance,

	// textures
	deferred_textures:    [dynamic]Texture_Load_Data,

	// fonts
	deferred_fonts:       [dynamic]FontLoadData,

	// sound
	sounds:               [dynamic]^Sound,
	music:                [dynamic]^Music,

	// shake system
	shake_instances:      [dynamic]^Shake_Instance,
	next_shake_id:        u32,

	// tween system
	pending_tweens:       [dynamic]^Tween_Instance,

	// fixed timestep system
	fixed_dt:             f32, // target timestep (i.e. 1/60 = 0.0166...)
	accumulator:          f32, // accumulated time for fixed steps
	max_frame_time:       f32, // cap to prevent spiral of death

	// GC stats for visualization
	gc_live:              uint,
	gc_threshold:         uint,
	gc_history:           [120]f32, // 2 seconds at 60fps
	gc_history_index:     int,

	// FPS stats for visualization
	fps_current:          f32,
	fps_history:          [120]f32, // 2 seconds at 60fps
	fps_history_index:    int,

	// tweens stats for visualization
	tweens_history:       [120]f32, // 2 seconds at 60fps
	tweens_history_index: int,

	// built-in fonts (exposed to gamedevs via Font::TINY etc, also used for error overlay)
	fonts:                struct {
		tiny:   rl.Font, // 5px - Font::TINY
		small:  rl.Font, // 8px - Font::SMALL
		medium: rl.Font, // 11px - Font::MEDIUM
		large:  rl.Font, // 15px - Font::LARGE
	},

	// mouse position caching per frame
	cached_mouse_frame:   u32,
	cached_mouse_world:   rl.Vector2,
	cached_mouse_ui:      rl.Vector2,

	// keys pressed this frame
	cached_keys_frame:    u32,
	cached_keys:          [10]rl.KeyboardKey,

	// pressed/release seen this frame
	input_state_frame:    u32,
	pressed_this_frame:   map[i32]bool,
	released_this_frame:  map[i32]bool,

	// collision bodies by layer
	registered_bodies:    map[^Body]mrb.Value,
	bodies_by_layer:      map[Collision_Layer][dynamic]^Body,
}

global_context: runtime.Context
NATIVE_TO_MRUBY_TYPE: map[typeid]^mrb.Data_Type
g: ^Engine_Memory
