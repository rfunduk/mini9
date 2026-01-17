package engine

import "core:encoding/endian"
import "core:fmt"
import "core:log"
import "core:strings"

Rom_Data :: map[string][]u8

@(private = "file")
ROM_MAGIC :: "MINI9"
@(private = "file")
ROM_VERSION :: 1

@(private = "file")
VERSION_SIZE :: size_of(u16)
@(private = "file")
DECOMPRESSED_SIZE :: size_of(u32)
@(private = "file")
COMPRESSION_TYPE_SIZE :: size_of(u8)
@(private = "file")
ROM_HEADER_SIZE :: len(ROM_MAGIC) + VERSION_SIZE + DECOMPRESSED_SIZE + COMPRESSION_TYPE_SIZE

@(private = "file")
Compression_Algorithm :: enum u8 {
	NONE = 0x0,
	ZLIB = 0x1,
	// LZ4  = 0x2,
}

rom_data_dump :: proc(rom_data: ^Rom_Data, use_compression := true) -> []u8 {
	if rom_data == nil || len(rom_data) == 0 { return nil }

	// create uncompressed ROM payload (no headers - just file table + data)
	uncompressed_payload := build_rom_payload(rom_data)
	defer delete(uncompressed_payload)

	// only compress if requested
	algorithm := Compression_Algorithm.NONE
	final_data := uncompressed_payload
	compressed_data: []u8 = nil
	defer { if compressed_data != nil { delete(compressed_data) } }

	if use_compression {
		// compress the ROM payload
		compress_ok: bool
		compressed_data, compress_ok = _compress_data(uncompressed_payload)

		// use compression if successful and saves space
		if compress_ok && compressed_data != nil && len(compressed_data) < len(uncompressed_payload) {
			algorithm = Compression_Algorithm.ZLIB
			final_data = compressed_data
		}
	}

	// calculate compression ratio for logging
	if algorithm != .NONE {
		ratio := f64(len(final_data)) / f64(len(uncompressed_payload)) * 100
		fmt.printf(
			"\n※ Compressed to %.1f%% of original, saving %d bytes",
			ratio,
			len(uncompressed_payload) - len(final_data),
		)
	}

	final_result := make([]u8, ROM_HEADER_SIZE + len(final_data))
	final_offset := 0

	// magic string
	copy(final_result[final_offset:final_offset + len(ROM_MAGIC)], ROM_MAGIC)
	final_offset += len(ROM_MAGIC)

	// version
	endian.put_u16(final_result[final_offset:], .Little, ROM_VERSION)
	final_offset += VERSION_SIZE

	// decompressed data size
	endian.put_u32(final_result[final_offset:], .Little, u32(len(uncompressed_payload)))
	final_offset += DECOMPRESSED_SIZE

	// compression algorithm
	final_result[final_offset] = u8(algorithm)
	final_offset += COMPRESSION_TYPE_SIZE

	// rom data
	copy(final_result[final_offset:], final_data)

	return final_result
}

rom_data_load :: proc(data: []u8, rom_data: ^Rom_Data) -> bool {
	header_size := len(ROM_MAGIC) + 2 + 4 + 1
	if len(data) < header_size { return false }

	offset := 0

	// verify magic
	if string(data[offset:offset + len(ROM_MAGIC)]) != ROM_MAGIC {
		log.errorf("failed to verify magic header %v", data[offset:offset + len(ROM_MAGIC)])
		return false
	}
	offset += len(ROM_MAGIC)

	// read version
	version, _ := endian.get_u16(data[offset:], .Little)
	offset += 2
	if version != ROM_VERSION {
		log.errorf("incorrect version %v vs %v", version, ROM_VERSION)
		return false
	}

	// read decompressed size
	decompressed_size, _ := endian.get_u32(data[offset:], .Little)
	offset += 4

	// read compression algorithm
	compression_algo := Compression_Algorithm(data[offset])
	offset += 1

	// decompress data
	compressed_data := data[offset:]
	decompressed_buffer: []u8
	defer { if decompressed_buffer != nil { delete(decompressed_buffer) } }

	switch compression_algo {
	case .NONE:
		// data is already uncompressed
		if len(compressed_data) != int(decompressed_size) { return false }
		decompressed_buffer = make([]u8, len(compressed_data))
		copy(decompressed_buffer, compressed_data)

	case .ZLIB:
		decompressed_buffer = _decompress_data(compressed_data, int(decompressed_size))
		if decompressed_buffer == nil { return false }

	// case .LZ4:
	// 	// LZ4 not implemented yet
	// 	return false

	case:
		// unknown compression algorithm
		return false
	}

	// parse decompressed ROM data
	return parse_rom_data(decompressed_buffer, rom_data)
}

@(private = "file")
parse_rom_data :: proc(data: []u8, rom_data: ^Rom_Data) -> bool {
	if len(data) < 4 { return false }

	offset := 0

	// read file count
	file_count, _ := endian.get_u32(data[offset:], .Little)
	offset += 4

	// clear existing data
	clear(rom_data)

	// read file table and data
	for _ in 0 ..< file_count {
		if offset + 4 > len(data) { return false }

		// read path length
		path_len_u32, _ := endian.get_u32(data[offset:], .Little)
		path_len := int(path_len_u32)
		offset += 4

		if offset + path_len > len(data) { return false }

		// read path
		path := string(data[offset:offset + path_len])
		offset += path_len

		if offset + 8 > len(data) { return false }

		// read data offset and size
		data_offset_u32, _ := endian.get_u32(data[offset:], .Little)
		data_offset := int(data_offset_u32)
		offset += 4

		data_size_u32, _ := endian.get_u32(data[offset:], .Little)
		data_size := int(data_size_u32)
		offset += 4

		if data_offset + data_size > len(data) { return false }

		// copy file data
		file_data := make([]u8, data_size)
		copy(file_data, data[data_offset:data_offset + data_size])
		rom_data[strings.clone(path)] = file_data
	}

	return true
}

@(private = "file")
build_rom_payload :: proc(rom_data: ^Rom_Data) -> []u8 {
	// calculate size needed for payload (without ROM headers)
	file_table_size := 0
	data_size := 0

	for path, data in rom_data {
		file_table_size += 4 + len(path) + 4 + 4 // path_len + path + data_offset + data_size
		data_size += len(data)
	}

	// payload: file_count + file_table + file_data
	payload_size := 4 + file_table_size + data_size
	result := make([]u8, payload_size)

	offset := 0

	endian.put_u32(result[offset:], .Little, u32(len(rom_data)))
	offset += 4

	// calculate data offsets (relative to start of payload)
	data_start_offset := 4 + file_table_size
	current_data_offset := data_start_offset

	// write file table
	for path, data in rom_data {
		// write path length and path
		endian.put_u32(result[offset:], .Little, u32(len(path)))
		offset += 4

		copy(result[offset:], path)
		offset += len(path)

		// write data offset and size
		endian.put_u32(result[offset:], .Little, u32(current_data_offset))
		offset += 4

		endian.put_u32(result[offset:], .Little, u32(len(data)))
		offset += 4

		current_data_offset += len(data)
	}

	// write file data
	for _, data in rom_data {
		copy(result[offset:], data)
		offset += len(data)
	}

	return result
}
