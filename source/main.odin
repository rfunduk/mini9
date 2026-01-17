package engine

import "core:math"
import "core:math/ease"
import rl "vendor:raylib"


@(export)
engine_update :: proc() { _engine_update() }

@(export)
engine_init :: proc(rom_data: ^Rom_Data) { _engine_init(rom_data) }

@(export)
engine_shutdown :: proc() {
	shutdown_ruby()
	rl.CloseAudioDevice()
	rl.UnloadRenderTexture(g.render_texture)
	ease.flux_destroy(g.flux)

	delete(g.cameras)
	delete(g.deferred_fonts)
	delete(g.deferred_textures)
	delete(g.shake_instances)
	delete(g.sounds)
	delete(g.music)
	delete(g.pending_tweens)

	free(g.rom_data)
	free(g)
}

@(export)
engine_is_running :: proc() -> bool {
	when ODIN_OS == .JS {
		return true
	} else {
		return g.run && !rl.WindowShouldClose()
	}
}

@(export)
engine_shutdown_window :: proc() {
	rl.CloseWindow()
}

engine_parent_window_size_changed :: proc(w, h: int) {
	scale := min(f32(w) / f32(g.resolution.x), f32(h) / f32(g.resolution.y))
	rl.SetWindowSize(i32(math.floor(g.resolution.x * scale)), i32(math.floor(g.resolution.y * scale)))
	calculate_screen_layout()
}
