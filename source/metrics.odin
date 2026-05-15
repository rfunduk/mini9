package engine

import "core:fmt"
import mrb "lib:mruby"
import rl "lib:raylib"

// GC graph window. Sampled every 2 frames @60fps -> 30 samples/sec.
@(private = "file")
GC_SAMPLES :: 300 // ~10s window
@(private = "file")
GC_LOWMARK_WIN :: 90 // ~3s trailing min -> post-GC baseline (display line)
@(private = "file")
GC_EMA_ALPHA :: f32(0.15)

@(private = "file")
gc_live: uint
@(private = "file")
gc_threshold: uint
@(private = "file")
gc_live_history: [GC_SAMPLES]f32 // absolute live object count
@(private = "file")
gc_ema_history: [GC_SAMPLES]f32 // EMA of live (the line the eye reads)
@(private = "file")
gc_threshold_history: [GC_SAMPLES]f32 // threshold overlay
@(private = "file")
gc_history_index: int
@(private = "file")
gc_ema: f32

// No automatic leak verdict — GC period, threshold autotune and warmup
// make any 10s auto-classification unsound (5 attempts, 5 failure modes).
// The cyan baseline line is the leak signal; we report drift% and let the
// human read it.

// Rolling arena peak: max over a trailing window, decays. Sampled every
// frame (cheap). All-time peak was sticky — one transient spike pinned it.
@(private = "file")
ARENA_SAMPLES :: 300 // ~5s @60fps
@(private = "file")
arena_current: int
@(private = "file")
arena_peak: int // rolling max over arena_ring
@(private = "file")
arena_ring: [ARENA_SAMPLES]int
@(private = "file")
arena_ring_index: int

@(private = "file")
fps_current: f32
@(private = "file")
fps_history: [120]f32 // 2 seconds at 60fps
@(private = "file")
fps_history_index: int

@(private = "file")
tweens_history: [120]f32 // 2 seconds at 60fps
@(private = "file")
tweens_history_index: int

@(private = "file")
draws_history: [120]f32 // 2 seconds at 60fps
@(private = "file")
draws_history_index: int

@(private = "file")
bodies_history: [120]f32 // 2 seconds at 60fps
@(private = "file")
bodies_history_index: int

Graph_Config :: struct {
	title:       string,
	color:       rl.Color,
	stack_index: int, // 0=bottom, 1=middle, 2=top
}

collect_metrics :: proc() {
	// Sample arena size every frame — cheap, and catches leaks fast.
	// At end-of-frame (after all save/restore wraps), arena should be low;
	// a steadily climbing peak indicates an odin-side path creating mruby
	// objects without arena scoping.
	arena_now := int(mrb.gc_arena_save(g.mrb_state))
	arena_current = arena_now
	arena_ring[arena_ring_index] = arena_now
	arena_ring_index = (arena_ring_index + 1) % len(arena_ring)
	arena_peak = 0
	for v in arena_ring {
		if v > arena_peak { arena_peak = v }
	}

	// update displayed stats only every 10 frames for readability
	if g.frame_count % 10 == 0 {
		gc_live = mrb.gc_live(g.mrb_state)
		gc_threshold = mrb.gc_threshold(g.mrb_state)
		fps_current = f32(rl.GetFPS())
	}

	// sample graph data every 2 frames
	if g.frame_count % 2 == 0 {
		live := f32(mrb.gc_live(g.mrb_state))
		threshold := f32(mrb.gc_threshold(g.mrb_state))
		if gc_ema == 0 { gc_ema = live } else { gc_ema += (live - gc_ema) * GC_EMA_ALPHA }
		gc_live_history[gc_history_index] = live
		gc_ema_history[gc_history_index] = gc_ema
		gc_threshold_history[gc_history_index] = threshold
		gc_history_index = (gc_history_index + 1) % len(gc_live_history)

		// also sample FPS - clamp relative to target FPS to avoid startup spikes
		fps := f32(rl.GetFPS())
		fps = clamp(fps, 0, f32(g.fps) * 3) // clamp to 3x target FPS
		fps_history[fps_history_index] = fps
		fps_history_index = (fps_history_index + 1) % len(fps_history)

		// sample active tweens count
		tweens := f32(len(g.flux.values))
		tweens_history[tweens_history_index] = tweens
		tweens_history_index = (tweens_history_index + 1) % len(tweens_history)

		// sample draw call count
		draws_history[draws_history_index] = f32(g.draw_calls)
		draws_history_index = (draws_history_index + 1) % len(draws_history)

		// sample physics body count
		bodies_history[bodies_history_index] = f32(physics_body_count())
		bodies_history_index = (bodies_history_index + 1) % len(bodies_history)
	}
}

// helper to calculate graph position based on stack index
get_graph_position :: proc(stack_index: int) -> (x: f32, y: f32) {
	graph_width :: 240
	graph_height :: 80
	margin :: 10

	screen_h := f32(rl.GetScreenHeight())
	graph_x := f32(margin)

	// calculate position based on available space
	total_graphs_height := f32(graph_height * 3 + margin * 4) // 3 graphs + margins
	graph_y: f32
	if total_graphs_height > screen_h {
		// not enough space - overlap graphs
		graph_y = screen_h - f32(graph_height * (stack_index + 1)) - f32(margin)
	} else {
		// enough space - stack properly
		graph_y = screen_h - f32(graph_height * (stack_index + 1)) - f32(margin * (stack_index + 1))
	}
	graph_y = max(f32(stack_index * graph_height), graph_y) // ensure graphs stay on screen

	return graph_x, graph_y
}

draw_graph_frame :: proc(x, y: f32, config: Graph_Config) {
	graph_width :: 240
	graph_height :: 80

	rl.DrawRectangle(i32(x), i32(y), graph_width, graph_height, {0, 0, 0, 180})
	rl.DrawRectangleLines(i32(x), i32(y), graph_width, graph_height, config.color)

	rl.DrawText(fmt.ctprintf("%s", config.title), i32(x + 5), i32(y + 2), 10, config.color)
}

// helper to draw reference lines
draw_reference_lines :: proc(x, y: f32, ratios: []f32, max_val: f32, target_val: f32 = 0) {
	graph_width :: 240
	graph_height :: 80
	graph_start_y := y + 40
	graph_draw_height := f32(graph_height - 45)

	for i in 0 ..< len(ratios) {
		ref_val := max_val * ratios[i]
		line_y := graph_start_y + graph_draw_height - (graph_draw_height * ratios[i])

		color := rl.Color{100, 100, 100, 50}
		if target_val > 0 && abs(ref_val - target_val) < max_val * 0.1 {
			color = {0, 255, 255, 50} // highlight target line
		}

		rl.DrawLine(i32(x), i32(line_y), i32(x + graph_width), i32(line_y), color)

		label := fmt.ctprintf("%.0f", ref_val)
		rl.DrawText(label, i32(x + graph_width - 25), i32(line_y - 5), 8, color)
	}
}

draw_history_lines :: proc(
	x, y: f32,
	history: []f32,
	history_index: int,
	max_val: f32,
	color_fn: proc(val: f32, max_val: f32) -> rl.Color,
) {
	graph_width :: 240
	graph_height :: 80
	graph_start_y := y + 40
	graph_draw_height := f32(graph_height - 45)

	point_width := f32(graph_width) / f32(len(history))

	for i in 1 ..< len(history) {
		prev_idx := (history_index + i - 1) % len(history)
		curr_idx := (history_index + i) % len(history)

		prev_val := history[prev_idx] / max_val
		curr_val := history[curr_idx] / max_val

		if history[curr_idx] < 0 { continue }

		x1 := x + f32(i - 1) * point_width
		x2 := x + f32(i) * point_width
		y1 := graph_start_y + graph_draw_height - (prev_val * graph_draw_height)
		y2 := graph_start_y + graph_draw_height - (curr_val * graph_draw_height)

		color := color_fn(history[curr_idx], max_val)
		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), color)
	}
}

fps_color_fn :: proc(val: f32, max_val: f32) -> rl.Color {
	if val < 30 { return rl.RED } else if val < 50 { return rl.YELLOW }
	return rl.GREEN
}

draw_fps_graph :: proc() {
	config := Graph_Config {
		title       = "FPS",
		color       = {0, 255, 255, 255},
		stack_index = 1,
	}
	graph_x, graph_y := get_graph_position(config.stack_index)

	draw_graph_frame(graph_x, graph_y, config)

	fps_text := fmt.ctprintf("Current: %3.0f", fps_current)
	rl.DrawText(fps_text, i32(graph_x + 5), i32(graph_y + 14), 10, rl.WHITE)

	sum: f32 = 0
	count: int = 0
	for i in 0 ..< len(fps_history) {
		if fps_history[i] > 0 {
			sum += fps_history[i]
			count += 1
		}
	}
	avg_fps := count > 0 ? sum / f32(count) : 0
	avg_text := fmt.ctprintf("Avg: %3.0f", avg_fps)
	rl.DrawText(avg_text, i32(graph_x + 5), i32(graph_y + 26), 10, rl.GRAY)

	max_fps := f32(g.fps) * 3
	ratios := [4]f32{0.5, 1.0, 1.5, 2.0}
	draw_reference_lines(graph_x, graph_y, ratios[:], max_fps, f32(g.fps))

	draw_history_lines(graph_x, graph_y, fps_history[:], fps_history_index, max_fps, fps_color_fn)
}

// Draw a chronological series (already unrolled, oldest-first) as a polyline.
@(private = "file")
draw_series :: proc(x, y: f32, chrono: []f32, max_val: f32, color: rl.Color) {
	graph_width :: 240
	graph_height :: 80
	graph_start_y := y + 40
	graph_draw_height := f32(graph_height - 45)
	point_width := f32(graph_width) / f32(len(chrono))

	for i in 1 ..< len(chrono) {
		if chrono[i] < 0 || chrono[i - 1] < 0 { continue }
		pv := chrono[i - 1] / max_val
		cv := chrono[i] / max_val
		x1 := x + f32(i - 1) * point_width
		x2 := x + f32(i) * point_width
		y1 := graph_start_y + graph_draw_height - (pv * graph_draw_height)
		y2 := graph_start_y + graph_draw_height - (cv * graph_draw_height)
		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), color)
	}
}

// compact count: 842, 16.2k, 1.50M
@(private = "file")
humanize :: proc(v: f32) -> string {
	if v < 1000 { return fmt.tprintf("%.0f", v) }
	if v < 1e6 { return fmt.tprintf("%.1fk", v / 1000) }
	return fmt.tprintf("%.2fM", v / 1e6)
}

draw_memory_graph :: proc() {
	config := Graph_Config {
		title       = "GC Memory",
		color       = rl.GREEN,
		stack_index = 0,
	}
	graph_x, graph_y := get_graph_position(config.stack_index)

	L :: GC_SAMPLES

	// unroll ring buffers into chronological (oldest-first) order
	live: [L]f32
	ema: [L]f32
	thr: [L]f32
	base: [L]f32 // trailing-min of live -> post-GC baseline
	for k in 0 ..< L {
		idx := (gc_history_index + k) % L
		live[k] = gc_live_history[idx]
		ema[k] = gc_ema_history[idx]
		thr[k] = gc_threshold_history[idx]
	}
	for k in 0 ..< L {
		lo: f32 = -1
		lo_from := max(0, k - GC_LOWMARK_WIN + 1)
		for j in lo_from ..= k {
			if live[j] <= 0 { continue }
			if lo < 0 || live[j] < lo { lo = live[j] }
		}
		base[k] = lo
	}

	// absolute y-scale: fit both live and threshold, rounded up
	max_val: f32 = 1
	for k in 0 ..< L {
		if live[k] > max_val { max_val = live[k] }
		if thr[k] > max_val { max_val = thr[k] }
	}
	{
		mag := f32(1)
		for mag * 10 < max_val { mag *= 10 }
		max_val = (f32(int(max_val / mag)) + 1) * mag
	}

	// No verdict. The cyan baseline line is the leak signal — flat = fine,
	// climbing = leak. We only report the drift number; the human reads it.
	// (5 heuristic verdicts, 5 failure modes — GC period, threshold autotune
	// and warmup make any 10s auto-classification unsound.)
	base_now: f32 = -1
	for k := L - 1; k >= 0; k -= 1 {
		if base[k] > 0 { base_now = base[k]; break }
	}
	first_i := -1
	last_i := -1
	for k in 0 ..< L {
		if base[k] > 0 {
			if first_i < 0 { first_i = k }
			last_i = k
		}
	}
	drift_pct: f32 = 0
	if first_i >= 0 && last_i > first_i {
		drift_pct = (base[last_i] - base[first_i]) / max(base[first_i], 1) * 100
	}

	draw_graph_frame(graph_x, graph_y, config)

	base_disp := base_now > 0 ? base_now : 0
	live_text := fmt.ctprintf("Live: %-7s Base: %s", humanize(f32(gc_live)), humanize(base_disp))
	rl.DrawText(live_text, i32(graph_x + 5), i32(graph_y + 14), 10, rl.WHITE)

	drift_text := fmt.ctprintf("Thresh: %-7s drift:%+4.0f%%", humanize(f32(gc_threshold)), drift_pct)
	rl.DrawText(drift_text, i32(graph_x + 5), i32(graph_y + 26), 10, rl.GRAY)

	// Arena: rolling peak over ~5s (not all-time). Climbing unbounded ->
	// odin-side create_* without arena save/restore. Healthy = near zero.
	arena_color := rl.GRAY
	if arena_peak > 500 { arena_color = rl.YELLOW }
	if arena_peak > 2000 { arena_color = rl.RED }
	arena_text := fmt.ctprintf("Arena:%4d  Pk(5s):%5d", arena_current, arena_peak)
	rl.DrawText(arena_text, i32(graph_x + 5), i32(graph_y + 38), 10, arena_color)

	ratios := [4]f32{0.25, 0.5, 0.75, 1.0}
	draw_reference_lines(graph_x, graph_y, ratios[:], max_val)

	// threshold overlay (gray), raw live (faint), EMA (green, main read),
	// baseline (cyan leak indicator) — drawn back-to-front
	draw_series(graph_x, graph_y, thr[:], max_val, {120, 120, 120, 160})
	draw_series(graph_x, graph_y, live[:], max_val, {0, 200, 0, 90})
	draw_series(graph_x, graph_y, ema[:], max_val, {0, 230, 0, 255})
	draw_series(graph_x, graph_y, base[:], max_val, {0, 220, 255, 220})
}

draw_tweens_graph :: proc() {
	graph_width :: 240
	graph_height :: 80
	margin :: 10

	screen_h := f32(rl.GetScreenHeight())
	graph_x := f32(margin)

	// calculate position based on available space
	total_graphs_height := f32(graph_height * 3 + margin * 4) // 3 graphs + margins
	graph_y: f32
	if total_graphs_height > screen_h {
		// not enough space - overlap graphs
		graph_y = screen_h - f32(graph_height * 3) - f32(margin)
	} else {
		// enough space - stack properly
		graph_y = screen_h - f32(graph_height * 3) - f32(margin * 3)
	}
	graph_y = max(0, graph_y) // ensure it stays on screen

	rl.DrawRectangle(i32(graph_x), i32(graph_y), graph_width, graph_height, {0, 0, 0, 180})
	rl.DrawRectangleLines(i32(graph_x), i32(graph_y), graph_width, graph_height, {255, 165, 0, 255})

	rl.DrawText("Tweens", i32(graph_x + 5), i32(graph_y + 2), 10, {255, 165, 0, 255})

	active_tweens := len(g.flux.values)

	count_text := fmt.ctprintf("Active: %3d", active_tweens)
	rl.DrawText(count_text, i32(graph_x + 5), i32(graph_y + 14), 10, rl.WHITE)

	sum: f32 = 0
	count: int = 0
	for i in 0 ..< len(tweens_history) {
		if tweens_history[i] >= 0 {
			sum += tweens_history[i]
			count += 1
		}
	}
	avg_tweens := count > 0 ? sum / f32(count) : 0

	avg_text := fmt.ctprintf("Avg: %3.0f", avg_tweens)
	rl.DrawText(avg_text, i32(graph_x + 5), i32(graph_y + 26), 10, rl.GRAY)

	graph_start_y := graph_y + 40
	graph_draw_height := f32(graph_height - 45)

	// find max value in history for scaling
	max_tweens: f32 = 100 // minimum scale
	for i in 0 ..< len(tweens_history) {
		if tweens_history[i] > max_tweens {
			max_tweens = tweens_history[i]
		}
	}

	// round up to nice number
	if max_tweens < 50 {
		max_tweens = 50
	} else if max_tweens < 100 {
		max_tweens = 100
	} else if max_tweens < 250 {
		max_tweens = 250
	} else if max_tweens < 500 {
		max_tweens = 500
	} else {
		max_tweens = ((max_tweens / 100) + 1) * 100
	}

	// draw horizontal reference lines
	reference_lines := [4]f32{0.25, 0.5, 0.75, 1.0}
	for i in 0 ..< 4 {
		ref_count := max_tweens * reference_lines[i]
		y := graph_start_y + graph_draw_height - (graph_draw_height * reference_lines[i])

		color := rl.Color{100, 100, 100, 50}
		rl.DrawLine(i32(graph_x), i32(y), i32(graph_x + graph_width), i32(y), color)

		label := fmt.ctprintf("%.0f", ref_count)
		rl.DrawText(label, i32(graph_x + graph_width - 25), i32(y - 5), 8, color)
	}

	point_width := f32(graph_width) / f32(len(tweens_history))

	for i in 1 ..< len(tweens_history) {
		// calculate indices for scrolling effect
		prev_idx := (tweens_history_index + i - 1) % len(tweens_history)
		curr_idx := (tweens_history_index + i) % len(tweens_history)

		prev_val := tweens_history[prev_idx] / max_tweens // scale to 0-1 range
		curr_val := tweens_history[curr_idx] / max_tweens

		if tweens_history[curr_idx] < 0 { continue }

		x1 := graph_x + f32(i - 1) * point_width
		x2 := graph_x + f32(i) * point_width
		y1 := graph_start_y + graph_draw_height - (prev_val * graph_draw_height)
		y2 := graph_start_y + graph_draw_height - (curr_val * graph_draw_height)

		tweens := tweens_history[curr_idx]
		color := rl.Color{255, 165, 0, 255} // orange
		if tweens >
		   max_tweens * 0.75 { color = rl.RED } else if tweens > max_tweens * 0.5 { color = rl.YELLOW }

		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), color)
	}
}

draw_bodies_graph :: proc() {
	graph_width :: 240
	graph_height :: 80
	margin :: 10
	stack :: 5 // 5th from bottom (above draws)

	screen_h := f32(rl.GetScreenHeight())
	graph_x := f32(margin)

	total_graphs_height := f32(graph_height * stack + margin * (stack + 1))
	graph_y: f32
	if total_graphs_height > screen_h {
		graph_y = screen_h - f32(graph_height * stack) - f32(margin)
	} else {
		graph_y = screen_h - f32(graph_height * stack) - f32(margin * stack)
	}
	graph_y = max(0, graph_y)

	color_main :: rl.Color{100, 255, 180, 255} // teal-green

	rl.DrawRectangle(i32(graph_x), i32(graph_y), graph_width, graph_height, {0, 0, 0, 180})
	rl.DrawRectangleLines(i32(graph_x), i32(graph_y), graph_width, graph_height, color_main)

	rl.DrawText("Bodies", i32(graph_x + 5), i32(graph_y + 2), 10, color_main)

	total, dynamic_n, user_driven_n := physics_body_counts()

	count_text := fmt.ctprintf("Total: %3d  Dyn: %3d  S/K: %3d", total, dynamic_n, user_driven_n)
	rl.DrawText(count_text, i32(graph_x + 5), i32(graph_y + 14), 10, rl.WHITE)

	sum: f32 = 0
	count: int = 0
	peak: f32 = 0
	for i in 0 ..< len(bodies_history) {
		if bodies_history[i] >= 0 {
			sum += bodies_history[i]
			count += 1
			if bodies_history[i] > peak { peak = bodies_history[i] }
		}
	}
	avg := count > 0 ? sum / f32(count) : 0

	avg_text := fmt.ctprintf("Avg: %3.0f  Peak: %3.0f", avg, peak)
	rl.DrawText(avg_text, i32(graph_x + 5), i32(graph_y + 26), 10, rl.GRAY)

	graph_start_y := graph_y + 40
	graph_draw_height := f32(graph_height - 45)

	max_val: f32 = 20
	for i in 0 ..< len(bodies_history) {
		if bodies_history[i] > max_val { max_val = bodies_history[i] }
	}
	if max_val < 50 {
		max_val = 50
	} else if max_val < 100 {
		max_val = 100
	} else if max_val < 250 {
		max_val = 250
	} else if max_val < 500 {
		max_val = 500
	} else {
		max_val = ((max_val / 100) + 1) * 100
	}

	reference_lines := [4]f32{0.25, 0.5, 0.75, 1.0}
	for i in 0 ..< 4 {
		ref_count := max_val * reference_lines[i]
		y := graph_start_y + graph_draw_height - (graph_draw_height * reference_lines[i])
		ref_color := rl.Color{100, 100, 100, 50}
		rl.DrawLine(i32(graph_x), i32(y), i32(graph_x + graph_width), i32(y), ref_color)
		label := fmt.ctprintf("%.0f", ref_count)
		rl.DrawText(label, i32(graph_x + graph_width - 25), i32(y - 5), 8, ref_color)
	}

	point_width := f32(graph_width) / f32(len(bodies_history))

	for i in 1 ..< len(bodies_history) {
		prev_idx := (bodies_history_index + i - 1) % len(bodies_history)
		curr_idx := (bodies_history_index + i) % len(bodies_history)

		prev_val := bodies_history[prev_idx] / max_val
		curr_val := bodies_history[curr_idx] / max_val

		if bodies_history[curr_idx] < 0 { continue }

		x1 := graph_x + f32(i - 1) * point_width
		x2 := graph_x + f32(i) * point_width
		y1 := graph_start_y + graph_draw_height - (prev_val * graph_draw_height)
		y2 := graph_start_y + graph_draw_height - (curr_val * graph_draw_height)

		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), color_main)
	}
}

draw_draws_graph :: proc() {
	graph_width :: 240
	graph_height :: 80
	margin :: 10
	stack :: 4 // 4th from bottom (above tweens)

	screen_h := f32(rl.GetScreenHeight())
	graph_x := f32(margin)

	total_graphs_height := f32(graph_height * stack + margin * (stack + 1))
	graph_y: f32
	if total_graphs_height > screen_h {
		graph_y = screen_h - f32(graph_height * stack) - f32(margin)
	} else {
		graph_y = screen_h - f32(graph_height * stack) - f32(margin * stack)
	}
	graph_y = max(0, graph_y)

	color_main :: rl.Color{255, 100, 255, 255} // magenta

	rl.DrawRectangle(i32(graph_x), i32(graph_y), graph_width, graph_height, {0, 0, 0, 180})
	rl.DrawRectangleLines(i32(graph_x), i32(graph_y), graph_width, graph_height, color_main)

	rl.DrawText("Draw Calls", i32(graph_x + 5), i32(graph_y + 2), 10, color_main)

	count_text := fmt.ctprintf("Current: %3d", g.draw_calls)
	rl.DrawText(count_text, i32(graph_x + 5), i32(graph_y + 14), 10, rl.WHITE)

	sum: f32 = 0
	count: int = 0
	peak: f32 = 0
	for i in 0 ..< len(draws_history) {
		if draws_history[i] >= 0 {
			sum += draws_history[i]
			count += 1
			if draws_history[i] > peak { peak = draws_history[i] }
		}
	}
	avg := count > 0 ? sum / f32(count) : 0

	avg_text := fmt.ctprintf("Avg: %3.0f  Peak: %3.0f", avg, peak)
	rl.DrawText(avg_text, i32(graph_x + 5), i32(graph_y + 26), 10, rl.GRAY)

	graph_start_y := graph_y + 40
	graph_draw_height := f32(graph_height - 45)

	max_val: f32 = 20 // minimum scale
	for i in 0 ..< len(draws_history) {
		if draws_history[i] > max_val { max_val = draws_history[i] }
	}
	if max_val < 50 {
		max_val = 50
	} else if max_val < 100 {
		max_val = 100
	} else if max_val < 250 {
		max_val = 250
	} else if max_val < 500 {
		max_val = 500
	} else {
		max_val = ((max_val / 100) + 1) * 100
	}

	reference_lines := [4]f32{0.25, 0.5, 0.75, 1.0}
	for i in 0 ..< 4 {
		ref_count := max_val * reference_lines[i]
		y := graph_start_y + graph_draw_height - (graph_draw_height * reference_lines[i])
		ref_color := rl.Color{100, 100, 100, 50}
		rl.DrawLine(i32(graph_x), i32(y), i32(graph_x + graph_width), i32(y), ref_color)
		label := fmt.ctprintf("%.0f", ref_count)
		rl.DrawText(label, i32(graph_x + graph_width - 25), i32(y - 5), 8, ref_color)
	}

	point_width := f32(graph_width) / f32(len(draws_history))

	for i in 1 ..< len(draws_history) {
		prev_idx := (draws_history_index + i - 1) % len(draws_history)
		curr_idx := (draws_history_index + i) % len(draws_history)

		prev_val := draws_history[prev_idx] / max_val
		curr_val := draws_history[curr_idx] / max_val

		if draws_history[curr_idx] < 0 { continue }

		x1 := graph_x + f32(i - 1) * point_width
		x2 := graph_x + f32(i) * point_width
		y1 := graph_start_y + graph_draw_height - (prev_val * graph_draw_height)
		y2 := graph_start_y + graph_draw_height - (curr_val * graph_draw_height)

		v := draws_history[curr_idx]
		line_color := color_main
		if v > max_val * 0.75 {
			line_color = rl.RED
		} else if v > max_val * 0.5 {
			line_color = rl.YELLOW
		}

		rl.DrawLine(i32(x1), i32(y1), i32(x2), i32(y2), line_color)
	}
}
