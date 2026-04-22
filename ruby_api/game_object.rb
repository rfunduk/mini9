# ENGINE native=Game_Object ruby=GameObject

class GameObject
  undef_method :dup, :clone

  def initialize(args={})
    @_attach_keys = []
    @_keys = []
    @_proc_keys = []

    args.entries.each do |key, val|
      if val.is_a?(Proc)
        @_proc_keys << key
        arity = val.parameters.length
        case arity
        when 0 then define_singleton_method(key.to_sym) { val.call }
        else define_singleton_method(key.to_sym) { |*args| val.call(*args.unshift(self)[0..arity-1]) }
        end
      else
        @_keys << key.to_sym
        # auto-wire engine-internal subcomponents (Spawner, etc.) via a
        # private `_attach(parent)` hook. User-facing `init:` proc is a
        # separate lifecycle concern; see native obj() for when it fires.
        @_attach_keys << key if val.respond_to?(:_attach)
        instance_variable_set("@#{key}", val)
        define_singleton_method(key) { instance_variable_get("@#{key}") }
        define_singleton_method("#{key}=") { |v| instance_variable_set("@#{key}", v) }
      end
    end

    @_attach_keys.each { |k| self.send(k)._attach(self) }
  end

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
  alias_method :inspect, :to_s

  def method_missing(name, *args)
    name_str = name.to_s
    if name_str.end_with?('=')
      key = name_str[0..-2]
      @_keys << key.to_sym
      instance_variable_set("@#{key}", args[0])
      define_singleton_method(key.to_sym) { instance_variable_get("@#{key}") }
      define_singleton_method(name_str.to_sym) { |v| instance_variable_set("@#{key}", v) }
    else
      super
    end
  end

  def init(*); end

  # clean up global helpers like v2/etc that aren't needed on GameObject
  # and could cause confusion
  ENGINE_METHODS.each do |m|
    undef_method m if method_defined?(m)
  end
end
