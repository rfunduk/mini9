# convenience storage to avoid ugly $globals
def g = $g ||= GlobalStore.new

# value-like and copyable (Circ, Rect, Vector2, Color, ...)
# clone shallow copies the ruby wrapper -> broken -> remove it. `dup` only
module ValueShape
  def self.included(base) = base.undef_method(:clone)
  def inspect = to_s
end

# a handle to a unique/native thing (Body, Camera, Sound, ...)
# no meaningful copy. make a new one instead
module NativeHandle
  def self.included(base) = base.undef_method(:dup, :clone)
  def inspect = to_s
end

# Mixin for "open" objects whose fields are created on demand: assigning an
# unknown `foo=` defines a `foo`/`foo=` accessor pair backed by an `@foo` ivar.
module DynamicAttributes
  def method_missing(name, *args)
    name_str = name.to_s
    return super unless name_str.end_with?("=")
    _define_value_field(name_str[0..-2], args[0])
  end

  # Define `key` (reader) and `key=` (writer) singleton methods backed by
  # `@key`, and store `value`.
  def _define_value_field(key, value)
    instance_variable_set("@#{key}", value)
    define_singleton_method(key) { instance_variable_get("@#{key}") }
    define_singleton_method("#{key}=") { |v| instance_variable_set("@#{key}", v) }
  end
end

# add try method to all objects for safe navigation
class Object
  def try(method_name, *args, &block)
    return nil if self.nil?
    return nil unless self.respond_to?(method_name)
    send(method_name, *args, &block)
  end
end

module Kernel
  alias_method :puts, :log
  alias_method :p, :log
end

# Hash-like with indifferent access — Symbol and String keys are equivalent.
# `data[:hp]` and `data["hp"]` look up the same entry. Used by the save
# system, also handy any time game data crosses a Symbol/String boundary
# (e.g. a `{foo: 1}` literal indexed by an `obj.name` String).
class IndifferentHash
  include Enumerable

  def initialize(h = nil)
    @h = {}
    h&.each { |k, v| @h[k.to_s] = v }
  end

  def [](k)            = @h[k.to_s]
  def []=(k, v)        = @h[k.to_s] = v
  def key?(k)          = @h.key?(k.to_s)
  alias_method :has_key?, :key?
  alias_method :include?, :key?
  alias_method :member?,  :key?
  def delete(k)        = @h.delete(k.to_s)
  def fetch(k, *a, &b) = @h.fetch(k.to_s, *a, &b)
  def dig(k, *r)       = (v = @h[k.to_s]; r.empty? ? v : v&.dig(*r))
  def each(&b)         = @h.each(&b)
  def keys             = @h.keys
  def values           = @h.values
  def size             = @h.size
  alias_method :length, :size
  def empty?           = @h.empty?
  def any?(&b)         = b ? @h.any?(&b) : !@h.empty?
  def to_h             = @h.dup
  def to_s             = @h.to_s
  alias_method :inspect, :to_s
  def merge(o)         = IndifferentHash.new(@h.merge(o.respond_to?(:to_h) ? o.to_h : o))
  def merge!(o)        = ((o.respond_to?(:to_h) ? o.to_h : o).each { |k, v| @h[k.to_s] = v }; self)
  def ==(o)            = o.is_a?(IndifferentHash) ? @h == o.to_h : @h == o
end
