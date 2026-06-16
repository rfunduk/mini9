# ENGINE native=FSM ruby=FSM
# ENGINE native=State ruby=State

class FSM
  undef_method :dup, :clone
  def to_s = "FSM(current: #{state&.name || "<init>"})"
end

class State
  undef_method :dup, :clone

  # check state by symbol `s.is?(:idle)`
  def is?(other) = name == other

  def ==(other)
    return name == other if other.is_a?(Symbol)
    super
  end

  alias_method :===, :==

  def to_s = "State(#{name})"
  alias_method :inspect, :to_s
end

# `case state when :foo` sugar
class Symbol
  alias_method :__mini9_orig_eqq, :===
  def ===(other)
    return other == self if other.is_a?(State)
    __mini9_orig_eqq(other)
  end
end
