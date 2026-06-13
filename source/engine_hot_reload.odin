package engine

import "core:log"
import mrb "lib:mruby"

// Seconds between *.rb mtime scans. Coarse on purpose — saves are human-paced
// and the scan walks the game dir, so there's no reason to do it every frame.
@(private = "file")
HOT_RELOAD_POLL_INTERVAL :: f32(0.25)

@(private = "file")
poll_accum: f32

should_hot_reload :: proc(frame_time: f32) -> bool {
	poll_accum += frame_time
	if poll_accum < HOT_RELOAD_POLL_INTERVAL { return false }
	poll_accum = 0
	return _hot_reload_dirty()
}

perform_hot_reload :: proc() {
	prev := g.phase
	g.phase = .RELOAD
	defer g.phase = prev

	// Bound the arena: a reload allocates a pile of transient ruby values
	// (re-imported modules, rebuilt consts) that must not pin into the next frame.
	arena := mrb.gc_arena_save(g.mrb_state)
	defer mrb.gc_arena_restore(g.mrb_state, arena)

	// Remember existing top-level GameObjects before the re-run rebuilds them.
	hot_reload_ruby_call("snapshot")

	if !load_main_rb(panic_on_error = false) {
		// Bad edit: the exception was already logged by load_main_rb. Keep the
		// old world intact and let the next save retry.
		log.warn("[hot-reload] reload failed, keeping previous game state")
		return
	}

	// Merge the freshly-built definitions back onto the surviving objects:
	// swap behavior procs + add new fields, preserve runtime state + identity.
	hot_reload_ruby_call("commit")

	// The re-run re-defined the top-level callbacks on Object; re-resolve (and
	// re-undef) them so update/draw/ui dispatch to the new procs.
	determine_game_callbacks()
	log.info("[hot-reload] reloaded")
}

// Drive the ruby-side HotReload module by global lookup ($hot_reload), the same
// pattern as call_user_tasks reaching $tasks. No args, no return value used.
@(private = "file")
hot_reload_ruby_call :: proc(method: cstring) {
	if g.mrb_state == nil { return }
	mod := mrb.gv_get(g.mrb_state, mrb.intern_cstr(g.mrb_state, "$hot_reload"))
	if mod == mrb.NIL { return }
	mrb.funcall_argv(g.mrb_state, mod, mrb.intern_cstr(g.mrb_state, method), 0, nil)
}
