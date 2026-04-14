# ENGINE native=Timer_Instance ruby=Timer

class Timer
  # NOTE: methods implemented in native code

  def to_s = "Timer(#{repeating? ? "every" : "after"} #{interval}s, elapsed: #{elapsed}, finished?: #{finished?}, cancelled?: #{cancelled?})"
  alias_method :inspect, :to_s
end
