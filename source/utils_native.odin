#+build !wasm32
#+build !wasm64p32

package engine

import "core:log"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import zlib "vendor:zlib"

init_game_window :: proc() {
	aspect_ratio := g.resolution.x / g.resolution.y
	initial_h := i32(600)
	initial_w := i32(f32(initial_h) * aspect_ratio)

	rl.InitWindow(initial_w, initial_h, strings.clone_to_cstring(g.title))

	// now get monitor dimensions and resize/position properly
	m := rl.GetCurrentMonitor()
	monitor_w := rl.GetMonitorWidth(m)
	monitor_h := rl.GetMonitorHeight(m)

	// calculate final window size (maintain aspect ratio, fit with 20px margins)
	available_h := monitor_h - 120 * 2
	available_w := monitor_w - 60 * 2

	window_h := available_h
	window_w := i32(f32(window_h) * aspect_ratio)

	if window_w > available_w {
		window_w = available_w
		window_h = i32(f32(window_w) / aspect_ratio)
	}

	if window_w < 128 { window_w = 128 }
	if window_h < 128 { window_h = 128 }

	rl.SetWindowSize(window_w, window_h)

	// position on left side with margin, centered vertically
	pos_x: i32 = monitor_w - window_w - 30
	pos_y: i32 = (monitor_h - window_h) / 2
	rl.SetWindowPosition(pos_x, pos_y)
}

get_rom_data :: proc(path: string) -> ^Rom_Data {
	rom_file_data, read_ok := os.read_entire_file(path)
	if read_ok {
		rom_data := new(Rom_Data)
		if rom_data_load(rom_file_data, rom_data) {
			log.infof("✓ Loaded ROM: %s (%d bytes)", path, len(rom_file_data))
			return rom_data
		} else {
			log.errorf("Error: Failed to parse ROM file: %s", path)
			os.exit(1)
		}
	} else {
		log.errorf("Error: Failed to read ROM file: %s", path)
		os.exit(1)
	}
}

_read_entire_file :: proc(
	name: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	data: []byte,
	success: bool,
) {
	// first check ROM data if available
	if g.rom_data != nil {
		if rom_file_data, found := g.rom_data[name]; found {
			// return direct reference to ROM data (no allocation needed)
			return rom_file_data, true
		}
	}

	// fall back to filesystem
	return os.read_entire_file(name, allocator, loc)
}

_write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return os.write_entire_file(name, data, truncate)
}

_file_exists :: proc(name: string) -> bool {
	// first check ROM data if available
	if g.rom_data != nil {
		if _, found := g.rom_data[name]; found {
			return true
		}
	}

	// fall back to filesystem
	return os.exists(name)
}

ensure_audio_initialized :: proc() {  }

calculate_screen_layout :: proc() {
	// get screen dimensions (handle fullscreen mode properly)
	screen_w, screen_h: f32
	if rl.IsWindowFullscreen() {
		monitor := rl.GetCurrentMonitor()
		screen_w = f32(rl.GetMonitorWidth(monitor))
		screen_h = f32(rl.GetMonitorHeight(monitor))
	} else {
		screen_w = f32(rl.GetScreenWidth())
		screen_h = f32(rl.GetScreenHeight())
	}

	game_w := g.resolution.x
	game_h := g.resolution.y

	// calculate scale factor to fit game in screen while maintaining aspect ratio
	scale_x := screen_w / game_w
	scale_y := screen_h / game_h
	scale := min(scale_x, scale_y)

	// calculate centered dest rect
	scaled_w := game_w * scale
	scaled_h := game_h * scale
	g.dest_rect = {
		x      = (screen_w - scaled_w) / 2,
		y      = (screen_h - scaled_h) / 2,
		width  = scaled_w,
		height = scaled_h,
	}
}

set_cursor_visible :: proc(visible: bool) {
	if visible {
		rl.ShowCursor()
	} else {
		rl.HideCursor()
	}
}

_compress_data :: proc(data: []u8) -> (compressed: []u8, ok: bool) {
	if len(data) == 0 { return nil, false }

	stream: zlib.z_stream

	// initialize deflate stream
	result := zlib.deflateInit(&stream, zlib.DEFAULT_COMPRESSION)
	if result != zlib.OK { return nil, false }
	defer zlib.deflateEnd(&stream)

	// estimate compressed size (worst case is slightly larger than input)
	max_compressed_size := zlib.deflateBound(&stream, zlib.uLong(len(data)))
	compressed_buffer := make([]u8, max_compressed_size)

	// set up input
	stream.next_in = raw_data(data)
	stream.avail_in = zlib.uInt(len(data))

	// set up output
	stream.next_out = raw_data(compressed_buffer)
	stream.avail_out = zlib.uInt(len(compressed_buffer))

	// compress
	result = zlib.deflate(&stream, zlib.FINISH)
	if result != zlib.STREAM_END {
		delete(compressed_buffer)
		return nil, false
	}

	// create final result with actual compressed size
	actual_size := int(stream.total_out)
	final_compressed := make([]u8, actual_size)
	copy(final_compressed, compressed_buffer[:actual_size])
	delete(compressed_buffer)

	return final_compressed, true
}

_decompress_data :: proc(compressed_data: []u8, expected_size: int) -> []u8 {
	if len(compressed_data) == 0 || expected_size <= 0 {
		log.errorf("invalid size(s) %v %v", len(compressed_data), expected_size)
		return nil
	}

	stream: zlib.z_stream

	// initialize inflate stream (default window size for zlib format)
	result := zlib.inflateInit2(&stream, 15)
	if result != zlib.OK {
		log.errorf("zlib failed %v", result)
		return nil
	}
	defer zlib.inflateEnd(&stream)

	// allocate output buffer
	output_buffer := make([]u8, expected_size)

	// set up input
	stream.next_in = raw_data(compressed_data)
	stream.avail_in = zlib.uInt(len(compressed_data))

	// set up output
	stream.next_out = raw_data(output_buffer)
	stream.avail_out = zlib.uInt(expected_size)

	// decompress
	result = zlib.inflate(&stream, zlib.FINISH)
	if result != zlib.STREAM_END || int(stream.total_out) != expected_size {
		log.errorf("failed to decompress %v %v != %v", result, int(stream.total_out), expected_size)
		delete(output_buffer)
		return nil
	}

	return output_buffer
}
