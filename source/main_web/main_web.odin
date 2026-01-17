/*
These procs are the ones that will be called from `main_wasm.c`.
*/

package main_web

import engine ".."
import "base:runtime"
import "core:c"
import "core:mem"

@(private = "file")
web_context: runtime.Context

@(export)
main_start :: proc "c" () {
	context = runtime.default_context()

	// the WASM allocator doesn't seem to work properly in combination with
	// emscripten. there is some kind of conflict with how they manage memory.
	// so this sets up an allocator that uses emscripten's malloc.
	context.allocator = emscripten_allocator()
	runtime.init_global_temporary_allocator(1 * mem.Megabyte)

	// since we now use js_wasm32 we should be able to remove this and use
	// context.logger = log.create_console_logger(). however, that one produces
	// extra newlines on web. So it's a bug in that core lib.
	context.logger = create_emscripten_logger(.Info, {.Level, .Time, .Date})

	web_context = context

	// load ROM data from JavaScript
	rom_data: ^engine.Rom_Data = engine.get_rom_data("cart.rom")

	engine.engine_init(rom_data)
}

@(export)
main_update :: proc "c" () -> bool {
	context = web_context
	engine.engine_update()
	return engine.engine_is_running()
}

@(export)
main_end :: proc "c" () {
	context = web_context
	engine.engine_shutdown()
	engine.engine_shutdown_window()
}

@(export)
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
	context = web_context
	engine.engine_parent_window_size_changed(int(w), int(h))
}
