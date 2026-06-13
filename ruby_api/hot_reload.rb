# Surgical hot-reload:
#
#   1. snapshot  — before the re-run, remember every GameObject bound to a
#                  top-level constant or a `g.*` slot, keyed by that slot.
#   2. (engine re-runs main.rb, which builds fresh definitions)
#   3. commit    — for each slot that held a GameObject before AND holds a
#                  freshly-built one after, merge new -> old in place and rebind
#                  the slot back to the original object.
#
# The merge swaps handler procs (new behavior) and adds brand-new fields, but
# preserves existing field values (runtime state). Original object identity
# survives, so anything still holding a reference keeps working.
#
# Non-GameObject slots (scalars, arrays, textures, `SPEED = 5`) are left alone —
# the re-run reassigns them naturally, so tuning constants pick up new values.
module HotReload
  @consts  = {} # constant symbol => original GameObject
  @globals = {} # g.* ivar symbol => original GameObject

  class << self
    # Called by the engine immediately before re-running main.rb.
    def snapshot
      @consts.clear
      @globals.clear

      Object.constants.each do |name|
        val = (Object.const_get(name) rescue nil)
        @consts[name] = val if val.is_a?(GameObject)
      end

      if (store = $g)
        store.instance_variables.each do |iv|
          val = store.instance_variable_get(iv)
          @globals[iv] = val if val.is_a?(GameObject)
        end
      end
    end

    # Called by the engine immediately after re-running main.rb.
    def commit
      @consts.each do |name, old|
        fresh = (Object.const_get(name) rescue nil)
        next unless fresh.is_a?(GameObject) && !fresh.equal?(old)
        old._reload_merge!(fresh)
        Object.const_set(name, old)
      end

      if (store = $g)
        @globals.each do |iv, old|
          fresh = store.instance_variable_get(iv)
          next unless fresh.is_a?(GameObject) && !fresh.equal?(old)
          old._reload_merge!(fresh)
          store.instance_variable_set(iv, old)
        end
      end

      @consts.clear
      @globals.clear
    end
  end
end

# Rooted handle so the engine can drive the merge
$hot_reload = HotReload
