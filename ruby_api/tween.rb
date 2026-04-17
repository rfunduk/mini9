# ENGINE native=Tween_Instance ruby=Tween

class Tween
  undef_method :dup, :clone

  # easing constants live in `Easing` (e.g. Easing::LINEAR, Easing::CUBIC_IN_OUT)

  # NOTE: methods implemented in native code

  # returns the current tweened value
  # type depends on what was tweened: Numeric, Vector2, or Color
  def value; end

  # returns true if the tween is currently active (not finished)
  def running?; end

  # returns true if the tween has completed
  def finished?; end

  # returns true if the tween finished on this exact frame
  def just_finished?; end

  # returns the remaining time in seconds (0 if finished)
  def time_left; end

  # returns progress from 0.0 to 1.0 (0 = start, 1 = finished)
  def progress; end

  # stops the tween immediately
  def stop; end

  def to_s = "Tween(#{value}, running?: #{running?}, time_left: #{time_left}, progress: #{progress}, finished?: #{finished?}, just_finished?: #{just_finished?})"
  alias_method :inspect, :to_s
end
