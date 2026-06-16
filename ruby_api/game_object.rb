# ENGINE native=Game_Object ruby=GameObject

class GameObject
  include NativeHandle
  include DynamicAttributes

  def initialize(args={})
    @_attach_keys = []
    @_keys = []
    @_proc_keys = []
    @_procs = {}

    args.entries.each do |key, val|
      if val.is_a?(Proc)
        _define_handler(key, val)
      else
        @_attach_keys << key if val.respond_to?(:_attach)
        _define_value_field(key, val)
      end
    end

    @_attach_keys.each { |k| self.send(k)._attach(self) }
  end

  # Track the key (for hot reload / to_s) before defining the accessor pair.
  def _define_value_field(key, value)
    @_keys << key.to_sym
    super
  end

  # Install a handler proc as a singleton method, retaining the raw proc in
  # @_procs so hot reload can re-install (swap) it onto a surviving instance.
  # arity 0 -> bare call; otherwise `self` is threaded in as the first arg.
  def _define_handler(key, val)
    key = key.to_sym
    @_proc_keys << key unless @_proc_keys.include?(key)
    @_procs[key] = val
    arity = val.parameters.length
    case arity
    when 0 then define_singleton_method(key) { val.call }
    else define_singleton_method(key) { |*args| val.call(*args.unshift(self)[0..arity-1]) }
    end
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

  # The raw handler procs, keyed by name. Read by the reload merge.
  def _proc_table = @_procs

  # Snapshot of current value fields, keyed by name. Used by the reload merge
  # to discover brand-new fields (existing ones keep their live value).
  def _value_table
    t = {}
    @_keys.uniq.each { |k| t[k] = instance_variable_get("@#{k}") }
    t
  end

  # Merge a freshly-reloaded definition onto this (surviving) instance:
  #   - every handler proc is swapped to the new code (behavior updates live)
  #   - brand-new value fields are added
  #   - existing value fields keep their current value (runtime state survives)
  def _reload_merge!(fresh)
    fresh._proc_table.each { |key, prc| _define_handler(key, prc) }

    fresh._value_table.each do |key, val|
      next if @_keys.include?(key)
      _define_value_field(key, val)
      val._attach(self) if val.respond_to?(:_attach)
    end
  end
end
