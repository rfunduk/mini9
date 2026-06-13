#+build wasm32, wasm64p32

package engine

import "core:c"
import "core:log"
import "core:strings"
import rl "lib:raylib"

@(private = "file")
FILE :: struct {}

Whence :: enum c.int {
	SET,
	CUR,
	END,
}

foreign import js "expose"

// these are provided by our html shell
@(default_calling_convention = "contextless")
foreign js {
	web_set_cursor_visible :: proc(visible: c.bool) ---
	web_get_rom_size :: proc() -> c.int ---
	web_load_rom_data :: proc(ptr: rawptr) ---
	web_save_size :: proc() -> c.int ---
	web_save_read :: proc(ptr: rawptr) ---
	web_save_write :: proc(ptr: rawptr, len: c.int) ---
}

_save_file_read :: proc(allocator := context.allocator) -> (data: []byte, ok: bool) {
	n := int(web_save_size())
	if n <= 0 { return nil, false }
	buf := make([]byte, n, allocator)
	web_save_read(raw_data(buf))
	return buf, true
}

_save_file_write :: proc(data: []byte) -> bool {
	web_save_write(raw_data(data), c.int(len(data)))
	return true
}

// these will be linked in by emscripten.
@(default_calling_convention = "c")
foreign _ {
	fopen :: proc(filename, mode: cstring) -> ^FILE ---
	fseek :: proc(stream: ^FILE, offset: c.long, whence: Whence) -> c.int ---
	ftell :: proc(stream: ^FILE) -> c.long ---
	fclose :: proc(stream: ^FILE) -> c.int ---
	fread :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: ^FILE) -> c.size_t ---
	fwrite :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: ^FILE) -> c.size_t ---
}

init_game_window :: proc() {
	rl.InitWindow(i32(g.resolution.x), i32(g.resolution.y), strings.clone_to_cstring(g.title))
}

// similar to raylib's LoadFileData
_read_entire_file :: proc(
	name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: []byte,
	success: bool,
) {
	// first check cart data if available
	if g.rom_data != nil {
		if rom_file_data, found := g.rom_data[name]; found {
			// clone: see utils_native.odin for rationale. Callers assume
			// owned slices and `defer delete(...)`.
			out := make([]byte, len(rom_file_data), allocator, loc)
			copy(out, rom_file_data)
			return out, true
		}
	}

	log.errorf("File not found in cart: %v", name)
	return
}

// similar to raylib's SaveFileData.
//
// note: this can save during the current session, but I don't think you can
// save any data between sessions. So when you close the tab your saved files
// are gone. Perhaps you could communicate back to emscripten and save a cookie.
// or communicate with a server and tell it to save data.
_write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := fopen(strings.clone_to_cstring(name, context.temp_allocator), truncate ? "wb" : "ab")
	defer fclose(file)

	if file == nil {
		log.errorf("Failed to open '%v' for writing", name)
		return
	}

	bytes_written := fwrite(raw_data(data), 1, len(data), file)

	if bytes_written == 0 {
		log.errorf("Failed to write file %v", name)
		return
	} else if bytes_written != len(data) {
		log.errorf("File partially written, wrote %v out of %v bytes", bytes_written, len(data))
		return
	}

	log.debugf("File written successfully: %v", name)
	return true
}

_file_exists :: proc(name: string) -> bool {
	// first check cart data if available
	if g.rom_data != nil {
		if _, found := g.rom_data[name]; found {
			return true
		}
	}
	return false
}

// Web has no watchable filesystem — hot reload is a native dev-mode feature.
_hot_reload_dirty :: proc() -> bool { return false }

ensure_audio_initialized :: proc() {
	audio_device_was_initialized := rl.IsAudioDeviceReady()
	if !g.audio_initialized {
		// this will fail silently until user interaction occurs
		rl.InitAudioDevice()
		if rl.IsAudioDeviceReady() {
			g.audio_initialized = true
			load_deferred_sounds()
			load_deferred_music()
		}
	}
	if !audio_device_was_initialized && rl.IsAudioDeviceReady() {
		log.debugf("Audio device initialized")
	}
}

calculate_screen_layout :: proc() {
	// web builds stretch to fill canvas
	g.dest_rect = {0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
}

set_cursor_visible :: proc(visible: bool) {
	web_set_cursor_visible(c.bool(visible))
}

_compress_data :: proc(data: []u8) -> (compressed: []u8, ok: bool) {
	// no compression in web builds
	return nil, false
}

_decompress_data :: proc(compressed_data: []u8, expected_size: int) -> []u8 {
	// no decompression needed in web builds since carts are uncompressed
	log.error("Attempted to decompress data in web build - cart should be uncompressed")
	return nil
}

get_rom_data :: proc(_: cstring) -> ^Rom_Data {
	rom_size := web_get_rom_size()
	if rom_size > 0 {
		// allocate buffer for cart data
		rom_buffer := make([]u8, rom_size)

		// ask JavaScript to copy cart data into our buffer
		web_load_rom_data(raw_data(rom_buffer))

		// parse the cart data
		rom_data := new(Rom_Data)
		if rom_data_load(rom_buffer, rom_data) {
			log.infof("✓ Loaded cart data with %d files", len(rom_data))
			return rom_data
		} else {
			log.error("Failed to parse cart data")
			free(rom_data)
			return nil
		}
	}
	return nil
}
