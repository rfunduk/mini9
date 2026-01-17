# TODO, could this be implemented natively? is it worth it?

class FSM
  attr_reader :state

  def initialize(default:, states:)
    @default = default
    @states = states.each_with_object({}) do |state, memo|
      state.fsm = self
      memo[state.name] = state
    end
  end

  def init(this_obj) = @this_obj = this_obj

  def transition(state_name)
    next_state = @states[state_name]
    return if next_state == @state

    if @state
      args = [@this_obj, @state, next_state]
      @state._exit_arity.zero? ?
        @state._exit_proc.call() :
        @state._exit_proc.call(*args[0...@state._exit_arity])
    end

    last_state = @state
    @state = next_state
    if @state.nil?
      raise RuntimeError.new("No such state: #{state_name}")
    end

    args = [@this_obj, @state, last_state]
    @state._enter_arity.zero? ?
      @state._enter_proc.call() :
      @state._enter_proc.call(*args[0...@state._enter_arity])
  end

  def update(*args)
    transition(@default) if @state.nil?

    args.unshift(@state)
    args.unshift(@this_obj)

    @state._update_arity.zero? ?
      @state._update_proc.call() :
      @state._update_proc.call(*args[0...@state._update_arity])
  end

  def to_s = "FSM(current: #{state || "<initializing>"}, states: #{@states}, default: #{@default})"
end

class State
  attr_accessor :fsm
  attr_reader :name, :data
  attr_reader :_update_arity, :_enter_arity, :_exit_arity
  attr_reader :_update_proc, :_enter_proc, :_exit_proc

  def initialize(name, enter: nil, exit: nil, update: nil)
    @name = name
    @data = obj()

    # store procs
    @_enter_proc = enter || proc {}
    @_exit_proc = exit || proc {}
    @_update_proc = update || proc {}

    # cache update method arity
    @_update_arity = @_update_proc.parameters.length
    @_enter_arity = @_enter_proc.parameters.length
    @_exit_arity = @_exit_proc.parameters.length
  end

  def transition(...) = fsm.transition(...)

  def ==(other)
    return @name == other if other.is_a?(Symbol)
    super
  end

  alias_method :===, :==

  def to_s = "State(#{name})"
  alias_method :inspect, :to_s
end

def fsm(...) = FSM.new(...)
def state(...) = State.new(...)
