# ENGINE native=FSM ruby=FSM
# ENGINE native=State ruby=State

class FSM
  undef_method :dup, :clone
  def to_s = "FSM(current: #{state&.name || "<init>"})"
end

class State
  undef_method :dup, :clone

  def ==(other)
    return name == other if other.is_a?(Symbol)
    super
  end

  alias_method :===, :==

  def to_s = "State(#{name})"
  alias_method :inspect, :to_s
end
