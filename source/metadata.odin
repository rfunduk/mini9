package engine

import "core:encoding/json"
import "core:strings"

// User-authored cart metadata (SJSON file at source root, named `metadata`).
// Bundled into the cart at package time; read at runtime to drive title,
// and at package time to drive packaging exclusions.
Rom_Metadata :: struct {
	title:            string `json:"title"`,
	exclude_patterns: []string `json:"exclude"`,
}

// Parse the `metadata` file. Resolves through read_entire_file so it works
// in dev mode (file on disk, cwd = source dir) and packaged mode (entry in
// rom_data). Returns zero-value struct + ok=false when missing/malformed.
parse_metadata :: proc(allocator := context.allocator) -> (md: Rom_Metadata, ok: bool) {
	if !file_exists("metadata") { return }
	contents, read_ok := read_entire_file("metadata", context.temp_allocator)
	if !read_ok { return }
	if json.unmarshal(contents, &md, .SJSON, allocator) != nil { return }
	return md, true
}

// Pull title out of metadata into g.title before InitWindow. No-op if
// metadata is absent or title is empty.
apply_metadata_title :: proc() {
	md, ok := parse_metadata(context.temp_allocator)
	if !ok || len(md.title) == 0 { return }
	delete(g.title)
	g.title = strings.clone(md.title)
}
