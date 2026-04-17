package engine

import "core:log"
import "core:slice"
import mrb "lib:mruby"
import rl "vendor:raylib"

// Init-phase textures + all fonts + a white texel get packed into one atlas,
// so sprite / shape / line / text draws can all share a single bound texture
// and batch without flushing. Shapes + line() sample the white texel via
// SetShapesTexture / DrawTexturePro.
//
// Post-init texture loads (lazy) bypass the atlas and become standalone —
// they cost a texture switch each, documented as expected.

// 4096 is the WebGL 2 guaranteed minimum and universal on modern desktop
// hardware. Overflow logs a warning + spills into STANDALONE textures,
// so going over is survivable — just costs draw calls.
ATLAS_SIZE :: 4096
ATLAS_PADDING :: 2
WHITE_TEXEL_SIZE :: 4

@(private = "file")
Pending_Tex :: struct {
	ruby_obj: mrb.Value, // re-extract data pointer at pack time (GC-safe)
	image:    rl.Image, // decoded source image (we own it until packed)
}

@(private = "file")
Pending_Font :: struct {
	font:  ^rl.Font,
	image: rl.Image, // pixels read back from font.texture
}

@(private = "file")
pending: [dynamic]Pending_Tex

@(private = "file")
pending_fonts: [dynamic]Pending_Font

atlas_texture: rl.Texture2D
atlas_white_uv: rl.Rectangle
atlas_built: bool

queue_texture_for_atlas :: proc(ruby_obj: mrb.Value, image: rl.Image) {
	append(&pending, Pending_Tex{ruby_obj = ruby_obj, image = image})
}

queue_font_for_atlas :: proc(font: ^rl.Font) {
	if font.texture.id == 0 { return }
	image := rl.LoadImageFromTexture(font.texture)
	append(&pending_fonts, Pending_Font{font = font, image = image})
}

font_is_atlas_backed :: proc(font: ^rl.Font) -> bool {
	return atlas_built && atlas_texture.id != 0 && font.texture.id == atlas_texture.id
}

// Pack_Rect — input/output for shelf packer.
@(private = "file")
Pack_Kind :: enum {
	WHITE,
	TEXTURE,
	FONT,
}

@(private = "file")
Pack_Rect :: struct {
	kind:       Pack_Kind,
	idx:        int, // into pending (TEXTURE) or pending_fonts (FONT)
	w, h:       i32,
	x, y:       i32,
	was_packed: bool,
}

// shelf_pack — sort by height descending, fill rows left-to-right; new row
// when width exceeded. Wastes some vertical space but trivial and good
// enough for our typical mix of sprites + fonts.
@(private = "file")
shelf_pack :: proc(rects: []Pack_Rect, atlas_w, atlas_h: i32) -> (all_packed: bool) {
	slice.sort_by(rects, proc(a, b: Pack_Rect) -> bool { return a.h > b.h })

	all_packed = true
	cursor_x, cursor_y, row_h: i32 = 0, 0, 0

	for &r in rects {
		if r.w > atlas_w || r.h > atlas_h {
			r.was_packed = false
			all_packed = false
			continue
		}
		if cursor_x + r.w > atlas_w {
			// next row
			cursor_x = 0
			cursor_y += row_h
			row_h = 0
		}
		if cursor_y + r.h > atlas_h {
			r.was_packed = false
			all_packed = false
			continue
		}
		r.x = cursor_x
		r.y = cursor_y
		r.was_packed = true
		cursor_x += r.w
		if r.h > row_h { row_h = r.h }
	}
	return
}

pack_atlas :: proc() {
	// always build an atlas — even with zero textures, we still want the
	// white texel present so SetShapesTexture can route shapes + line()
	// through the atlas and batch.

	num_rects := len(pending) + len(pending_fonts) + 1
	rects := make([]Pack_Rect, num_rects, context.temp_allocator)

	for p, i in pending {
		rects[i] = Pack_Rect {
			kind = .TEXTURE,
			idx  = i,
			w    = p.image.width + ATLAS_PADDING,
			h    = p.image.height + ATLAS_PADDING,
		}
	}
	for p, i in pending_fonts {
		rects[len(pending) + i] = Pack_Rect {
			kind = .FONT,
			idx  = i,
			w    = p.image.width + ATLAS_PADDING,
			h    = p.image.height + ATLAS_PADDING,
		}
	}
	rects[num_rects - 1] = Pack_Rect {
		kind = .WHITE,
		w    = WHITE_TEXEL_SIZE + ATLAS_PADDING,
		h    = WHITE_TEXEL_SIZE + ATLAS_PADDING,
	}

	all_packed := shelf_pack(rects, ATLAS_SIZE, ATLAS_SIZE)

	composite := rl.GenImageColor(ATLAS_SIZE, ATLAS_SIZE, rl.Color{0, 0, 0, 0})

	for r in rects {
		if !r.was_packed {
			switch r.kind {
			case .WHITE:
				log.errorf("[atlas] white texel did not fit — atlas broken")
			case .TEXTURE:
				log.warnf("[atlas] texture did not fit; will load standalone")
			case .FONT:
				log.warnf("[atlas] font did not fit; will remain standalone")
			}
			continue
		}

		dst_x := f32(r.x)
		dst_y := f32(r.y)

		switch r.kind {
		case .WHITE:
			rl.ImageDrawRectangleRec(
				&composite,
				{dst_x, dst_y, WHITE_TEXEL_SIZE, WHITE_TEXEL_SIZE},
				rl.WHITE,
			)
			atlas_white_uv = rl.Rectangle {
				x      = dst_x + 1,
				y      = dst_y + 1,
				width  = WHITE_TEXEL_SIZE - 2,
				height = WHITE_TEXEL_SIZE - 2,
			}
		case .TEXTURE:
			p := &pending[r.idx]
			src_rect := rl.Rectangle{0, 0, f32(p.image.width), f32(p.image.height)}
			dst_rect := rl.Rectangle{dst_x, dst_y, f32(p.image.width), f32(p.image.height)}
			rl.ImageDraw(&composite, p.image, src_rect, dst_rect, rl.WHITE)
			t := extract_native(Texture, p.ruby_obj)
			if t != nil {
				t.tex_origin = rl.Vector2{dst_x, dst_y}
				t.w = f32(p.image.width)
				t.h = f32(p.image.height)
			}
		case .FONT:
			p := &pending_fonts[r.idx]
			src_rect := rl.Rectangle{0, 0, f32(p.image.width), f32(p.image.height)}
			dst_rect := rl.Rectangle{dst_x, dst_y, f32(p.image.width), f32(p.image.height)}
			rl.ImageDraw(&composite, p.image, src_rect, dst_rect, rl.WHITE)
		}
	}

	atlas_texture = rl.LoadTextureFromImage(composite)
	rl.SetTextureFilter(atlas_texture, .POINT)
	rl.UnloadImage(composite)

	rl.SetShapesTexture(atlas_texture, atlas_white_uv)

	// sprite textures → point at atlas
	for r in rects {
		if r.kind != .TEXTURE || !r.was_packed { continue }
		p := &pending[r.idx]
		t := extract_native(Texture, p.ruby_obj)
		if t != nil {
			t.tex = atlas_texture
			t.status = .LOADED
		}
		rl.UnloadImage(p.image)
	}

	// fonts → free original GPU texture, point at atlas, shift glyph rects
	for r in rects {
		if r.kind != .FONT || !r.was_packed { continue }
		p := &pending_fonts[r.idx]
		rl.UnloadTexture(p.font.texture) // free original glyph atlas (GPU)
		p.font.texture = atlas_texture
		for i in 0 ..< p.font.glyphCount {
			p.font.recs[i].x += f32(r.x)
			p.font.recs[i].y += f32(r.y)
		}
		rl.UnloadImage(p.image)
	}

	// spillover: textures that didn't fit → STANDALONE
	for r in rects {
		if r.kind != .TEXTURE || r.was_packed { continue }
		p := &pending[r.idx]
		standalone := rl.LoadTextureFromImage(p.image)
		rl.SetTextureFilter(standalone, .POINT)
		t := extract_native(Texture, p.ruby_obj)
		if t != nil {
			t.kind = .STANDALONE
			t.tex = standalone
			t.tex_origin = {0, 0}
			t.w = f32(p.image.width)
			t.h = f32(p.image.height)
			t.status = .LOADED
		}
		rl.UnloadImage(p.image)
	}

	// spillover fonts: unpacked fonts keep their original texture — drop image only
	for r in rects {
		if r.kind != .FONT || r.was_packed { continue }
		rl.UnloadImage(pending_fonts[r.idx].image)
	}

	clear(&pending)
	clear(&pending_fonts)
	atlas_built = true

	if !all_packed {
		log.warnf("[atlas] some items spilled out of atlas — consider larger atlas")
	}
}

cleanup_atlas :: proc() {
	delete(pending)
	delete(pending_fonts)
}
