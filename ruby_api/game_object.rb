# ENGINE native=Game_Object ruby=GameObject

class GameObject
  include UniqueHandle
  include DynamicAttributes
  include Attachable
  include Handlers

  def initialize(args={})
    @_attach_keys = []
    @_keys = []
    _init_handlers

    args.entries.each do |key, val|
      if val.is_a?(Proc)
        _define_handler(key, val)
      else
        @_attach_keys << key if val.respond_to?(:_attach)
        _define_value_field(key, val)
      end
    end
  end

  def _attach_children
    @_attach_keys.each { |k| self.send(k)._attach(self) }
  end

  # Track the key (for hot reload / to_s) before defining the accessor pair.
  def _define_value_field(key, value)
    @_keys << key.to_sym
    super
  end

  # NOTE: unlike a `foo=` assignment, []= only stores the ivar and tracks the
  # key — it deliberately does not define accessor methods.
  def []=(key, value)
    if value.is_a?(Proc)
      @_proc_keys << key
    else
      @_keys << key
    end
    instance_variable_set("@#{key}", value)
  end
  def [](key) = instance_variable_get("@#{key}")

  def to_s
    text = []
    attrs = (@_keys + %i{pos rotation scale visible}).each do |k|
      next if k.to_s.start_with?("_")
      text << "#{k}: #{send(k)}"
    end
    proc_attrs = @_proc_keys.each do |k|
      text << "#{k}: <fn>"
    end
    "GameObject(#{text.join(', ')})"
  end

  def init(*); end

  # --- hot reload support ---

  # Snapshot of current value fields, keyed by name. Used by the reload merge
  # to discover brand-new fields (existing ones keep their live value).
  def _value_table
    {}.tap do |t|
      @_keys.uniq.each { |k| t[k] = instance_variable_get("@#{k}") }
    end
  end

  # Merge a freshly-reloaded definition onto this (surviving) instance:
  #   - every handler proc is swapped to the new code (behavior updates live)
  #   - brand-new value fields are added
  #   - existing value fields keep their current value (runtime state survives)
  def _reload_merge!(fresh)
    super # swap handler procs

    fresh._value_table.each do |key, val|
      if @_keys.include?(key)
        old_val = instance_variable_get("@#{key}")
        if !old_val.equal?(val)
          [FSM, GameObject].each do
            if old_val.is_a?(_1) && val.is_a?(_1)
              old_val._reload_merge!(val)
              break
            end
          end
        end
        next
      end
      _define_value_field(key, val)
      val._attach(self) if val.respond_to?(:_attach)
    end

    # nuke duplicate physics body, if any
    fresh.body&.destroy
  end
end
