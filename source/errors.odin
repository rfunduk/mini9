package engine

import "core:fmt"
import "core:log"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

ERROR_RED :: rl.Color{200, 50, 50, 255}

// helper to check for Ruby exceptions
has_ruby_exception :: proc(state: ^mrb.State) -> bool {
	// on 64-bit systems, exc field is at offset 32 (5th pointer)
	// on 32-bit systems, it would be at offset 16
	offset: uintptr = 32
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 { offset = 16 }
	exc_ptr := cast(^rawptr)(uintptr(state) + offset)
	return exc_ptr^ != nil
}

handle_ruby_exception :: proc(exception: mrb.Value, ctx: Ruby_Call_Context) {
	// try different approaches to extract the error message
	error_str := "Ruby error occurred"

	// approach 1: Try to get the exception class name
	if exception != mrb.NIL {
		class_name := mrb.obj_classname(g.mrb_state, exception)
		if class_name != nil {
			class_str := string(cstring(class_name))
			error_str = fmt.tprintf("%s occurred", class_str)
		}
	}

	// approach 2: Try accessing message via mrb.iv_get (instance variable)
	mesg_sym := mrb.intern_cstr(g.mrb_state, "mesg")
	mesg_val := mrb.iv_get(g.mrb_state, exception, mesg_sym)
	if mesg_val != mrb.NIL {
		// try to convert message to string safely
		if mesg_str := mrb.string_value_cstr(g.mrb_state, mesg_val); mesg_str != nil {
			message := string(cstring(mesg_str))
			error_str = fmt.tprintf("%s: %s", error_str, message)
			log.errorf("Got exception message: %s", message)
		}
	}

	// get backtrace using mruby's built-in function
	backtrace := ""

	// temporarily restore exception state for mrb_exc_backtrace
	offset: uintptr = 32 // mrb->exc offset on 64-bit
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 { offset = 16 }
	exc_ptr := cast(^rawptr)(uintptr(g.mrb_state) + offset)

	old_exc := exc_ptr^
	exc_ptr^ = cast(rawptr)exception.w

	// backtrace printing is handled in the conditional branches below

	// extract backtrace for overlay
	backtrace_array := mrb.exc_backtrace(g.mrb_state, exception)
	if mrb.array_p(backtrace_array) {
		first_entry := mrb.ary_entry(backtrace_array, 0)
		if first_entry != mrb.NIL {
			if entry_cstr := mrb.str_to_cstr(g.mrb_state, first_entry); entry_cstr != nil {
				backtrace_line := string(cstring(entry_cstr))
				backtrace = fmt.tprintf("\n  at %s", backtrace_line)
			}
		}
	}

	// SAFE_DISPATCH is off - print to console only
	log.errorf("Ruby exception in %v -\n\n%s\n\n", ctx, error_str)
	mrb.print_backtrace(g.mrb_state)

	// restore exception state
	exc_ptr^ = old_exc

	when #config(SAFE_DISPATCH, false) {
		// show overlay when SAFE_DISPATCH is enabled
		full_error := backtrace != "" ? fmt.tprintf("%s%s", error_str, backtrace) : error_str
		ctx_str := fmt.tprintf("%v", ctx)
		show_error_overlay(full_error, ctx_str)
	} else {
		if ctx == .TWEEN_CALLBACK {
			log.infof("(tween continues...)")
		}
	}
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

	// draw error message (word wrapped)
	message_cstr := strings.clone_to_cstring(error_message, context.temp_allocator)
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
