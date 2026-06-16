# convenience storage to avoid ugly $globals
def g = $g ||= GlobalStore.new

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
