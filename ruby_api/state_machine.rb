# ENGINE native=FSM ruby=FSM

class FSM
  include UniqueHandle
  include Attachable
  def to_s = "FSM(current: #{state&.name || "<init>"})"
end

# States are plain Ruby objects, not GameObjects: handlers live in @_procs
# (hot reload swaps them via Handlers) and per-state data lives on `data`.
# The native FSM only holds the graph (parent/current/default/states) and
# dispatches by handler name.
class State
  include UniqueHandle
  include Handlers

  attr_reader :name, :fsm, :data

  def initialize(name, handlers, data_seed)
    @name = name
    @fsm = nil
    @data = obj()
    data_seed.each { |k, v| @data._define_value_field(k, v) } if data_seed.is_a?(Hash)
    _init_handlers
    handlers.each { |k, prc| _define_handler(k, prc) }
  end

  # Declarative: the FSM dispatches handlers; states expose no callable surface.
  def _install_handler_method(key, val); end

  # check state by symbol `s.is?(:idle)`
  def is?(other) = name == other

  def ==(other)
    return name == other if other.is_a?(Symbol)
    super
  end

  alias_method :===, :==

  def transition(name) = fsm&.transition(name)

  def to_s = "State(#{name})"

  # Engine hooks (native FSM calls these; not game API)
  def _set_fsm(f) @fsm = f end
  def _handler_for(kind) @_procs[kind] end
end

def state(name, enter: nil, exit: nil, update: nil, draw: nil, data: nil)
  handlers = {}
  { enter: enter, exit: exit, update: update, draw: draw }.each do |kind, prc|
    next if prc.nil?
    raise TypeError, "state(#{name.inspect}): #{kind}: must be a Proc" unless prc.is_a?(Proc)
    handlers[kind] = prc
  end
  State.new(name, handlers, data)
end

# `case state when :foo` sugar
class Symbol
  alias_method :__mini9_orig_eqq, :===
  def ===(other)
    return other == self if other.is_a?(State)
    __mini9_orig_eqq(other)
  end
end
