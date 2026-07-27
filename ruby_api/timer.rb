# ENGINE native=Timer_Instance ruby=Timer

class Timer
  include UniqueHandle
  include Attachable

  # NOTE: methods implemented in native code

  def to_s = "Timer(#{repeating? ? "every" : "after"} #{interval}s, elapsed: #{elapsed}, finished?: #{finished?}, cancelled?: #{cancelled?})"
end
