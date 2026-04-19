package engine

import "core:fmt"
import "core:log"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

ERROR_RED :: rl.Color{200, 50, 50, 255}

handle_ruby_exception :: proc(state: mrb.State, exception: mrb.Value, ctx: Ruby_Call_Context) {
	error_str := "Ruby error occurred"

	// get the exception class name (e.g. "NoMethodError", "TypeError")
	if exception != mrb.NIL {
		class_name := mrb.obj_classname(state, exception)
		if class_name != nil {
			class_str := string(cstring(class_name))
			error_str = fmt.tprintf("%s occurred", class_str)
		}
	}

	// extract the message by reading RException->mesg directly. mruby
	// stores exception messages as a struct field, NOT in the iv table,
	// so iv_get(exc, "mesg") always returns NIL. Going through the struct
	// field also means no funcall — safe to call here even though
	// mrb_state->exc is still set.
	if exception != mrb.NIL {
		mesg_val := mrb.exc_mesg(state, exception)
		if mesg_val != mrb.NIL && mrb.string_p(mesg_val) {
			if mesg_str := mrb.string_value_cstr(state, &mesg_val); mesg_str != nil {
				message := string(cstring(mesg_str))
				if len(message) > 0 {
					error_str = fmt.tprintf("%s: %s", error_str, message)
				}
			}
		}
	}

	// get backtrace using mruby's built-in function
	backtrace := ""

	// temporarily install our exception so mrb_print_backtrace / mrb_exc_backtrace
	// see it on the live VM, then restore whatever was there before.
	old_exc := mrb.swap_exception(state, exception)

	// extract backtrace for overlay
	backtrace_array := mrb.exc_backtrace(state, exception)
	if mrb.array_p(backtrace_array) {
		first_entry := mrb.ary_entry(backtrace_array, 0)
		if first_entry != mrb.NIL {
			if entry_cstr := mrb.str_to_cstr(state, first_entry); entry_cstr != nil {
				backtrace_line := string(cstring(entry_cstr))
				backtrace = fmt.tprintf("\n  at %s", backtrace_line)
			}
		}
	}

	log.errorf("Ruby exception in %v -\n\n%s\n\n", ctx, error_str)
	mrb.print_backtrace(state)

	// restore exception state
	_ = mrb.swap_exception(state, old_exc)

	// tween callbacks are protected + auto-continue (flux iteration must not
	// stall on one bad callback). all other contexts halt the game behind
	// the overlay — game debugging works in both debug and release builds.
	if ctx == .TWEEN_CALLBACK {
		log.infof("(tween continues...)")
	} else {
		full_error := backtrace != "" ? fmt.tprintf("%s%s", error_str, backtrace) : error_str
		ctx_str := fmt.tprintf("%v", ctx)
		show_error_overlay(full_error, ctx_str)
	}
}

// Greedy word-wrap that preserves existing newlines. Each "paragraph"
// (substring between \n) is broken at word boundaries so the rendered
// width never exceeds max_width. Returned string lives in temp_allocator.
@(private)
wrap_text :: proc(text: string, font: rl.Font, font_size, spacing, max_width: f32) -> string {
	out := strings.builder_make(context.temp_allocator)
	line := strings.builder_make(context.temp_allocator)

	flush_line :: proc(out, line: ^strings.Builder) {
		strings.write_string(out, strings.to_string(line^))
		strings.builder_reset(line)
	}

	for paragraph, p_idx in strings.split(text, "\n", context.temp_allocator) {
		if p_idx > 0 { strings.write_byte(&out, '\n') }
		strings.builder_reset(&line)

		for word in strings.split(paragraph, " ", context.temp_allocator) {
			if len(word) == 0 { continue }

			candidate: string
			if strings.builder_len(line) == 0 {
				candidate = word
			} else {
				candidate = fmt.tprintf("%s %s", strings.to_string(line), word)
			}
			cstr := strings.clone_to_cstring(candidate, context.temp_allocator)
			size := rl.MeasureTextEx(font, cstr, font_size, spacing)

			if size.x > max_width && strings.builder_len(line) > 0 {
				flush_line(&out, &line)
				strings.write_byte(&out, '\n')
				strings.write_string(&line, word)
			} else {
				if strings.builder_len(line) > 0 {
					strings.write_byte(&line, ' ')
				}
				strings.write_string(&line, word)
			}
		}

		if strings.builder_len(line) > 0 { flush_line(&out, &line) }
	}

	return strings.to_string(out)
}

show_error_overlay :: proc(error_message: string, ctx: string) {
	// create error overlay texture
	overlay_w: i32 = 192
	overlay_h: i32 = 192
	error_texture := rl.LoadRenderTexture(overlay_w, overlay_h)
	defer rl.UnloadRenderTexture(error_texture)

	// render error content to texture
	rl.BeginTextureMode(error_texture)
	rl.ClearBackground(ERROR_RED)

	// draw red header
	rl.DrawRectangle(0, 0, overlay_w, 40, ERROR_RED)

	// draw error text
	header_text := fmt.tprintf("Error in %s:", ctx)
	header_cstr := strings.clone_to_cstring(header_text, context.temp_allocator)
	rl.DrawTextEx(g.fonts.medium, header_cstr, {10, 10}, f32(g.fonts.medium.baseSize), 1.0, rl.WHITE)

	// draw error message, word-wrapped to the overlay width (with side padding)
	wrapped := wrap_text(error_message, g.fonts.small, f32(g.fonts.small.baseSize), 1.0, f32(overlay_w - 20))
	message_cstr := strings.clone_to_cstring(wrapped, context.temp_allocator)
	rl.DrawTextEx(g.fonts.small, message_cstr, {10, 60}, f32(g.fonts.small.baseSize), 1.0, rl.WHITE)

	// draw dismiss instruction
	dismiss_text := "Press ESC to dismiss or Q to quit"
	dismiss_cstr := strings.clone_to_cstring(dismiss_text, context.temp_allocator)
	rl.DrawTextEx(
		g.fonts.small,
		dismiss_cstr,
		{10, f32(overlay_h - 15)},
		f32(g.fonts.small.baseSize),
		1.0,
		{180, 180, 180, 255},
	)

	rl.EndTextureMode()

	// error display loop - halts game until dismissed
	cooldown_frames: i32 = 0
	for engine_is_running() {
		if rl.IsKeyPressed(.Q) {
			// immediate quit on Q key
			g.run = false
			return
		}

		if rl.IsKeyPressed(.ESCAPE) {
			if cooldown_frames == 0 {
				cooldown_frames = 3
			}
		}

		if cooldown_frames > 0 {
			cooldown_frames -= 1
			if cooldown_frames == 0 {
				break
			}
		}
		rl.BeginDrawing()

		// draw current game frame (frozen)
		rl.BeginMode2D({zoom = 1})
		rl.ClearBackground(rl.BLACK)
		rl.DrawTexturePro(
			texture = g.render_texture.texture,
			source = {0, 0, g.resolution.x, -g.resolution.y},
			dest = g.dest_rect,
			origin = {0, 0},
			rotation = 0,
			tint = rl.WHITE,
		)
		rl.EndMode2D()

		// draw error overlay scaled to 80% of smaller screen dimension
		screen_w := f32(rl.GetScreenWidth())
		screen_h := f32(rl.GetScreenHeight())

		// calculate scale to be 80% of the smaller dimension
		smaller_dim := min(screen_w, screen_h)
		target_size := smaller_dim * 0.8
		scale := target_size / f32(overlay_w) // overlay_w == overlay_h (256)

		// calculate centered position
		scaled_w := f32(overlay_w) * scale
		scaled_h := f32(overlay_h) * scale
		overlay_x := (screen_w - scaled_w) / 2
		overlay_y := (screen_h - scaled_h) / 2

		rl.DrawTexturePro(
			texture = error_texture.texture,
			source = {0, 0, f32(overlay_w), -f32(overlay_h)},
			dest = {overlay_x, overlay_y, scaled_w, scaled_h},
			origin = {0, 0},
			rotation = 0,
			tint = rl.WHITE,
		)

		rl.EndDrawing()
	}
}
