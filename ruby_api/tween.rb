# ENGINE native=Tween_Instance ruby=Tween

class Tween
  # easing constants - mapped to Odin's ease.Ease enum
  LINEAR = 0

  # quadratic
  QUADRATIC_IN = 1
  QUADRATIC_OUT = 2
  QUADRATIC_IN_OUT = 3

  # cubic
  CUBIC_IN = 4
  CUBIC_OUT = 5
  CUBIC_IN_OUT = 6

  # quartic
  QUARTIC_IN = 7
  QUARTIC_OUT = 8
  QUARTIC_IN_OUT = 9

  # quintic
  QUINTIC_IN = 10
  QUINTIC_OUT = 11
  QUINTIC_IN_OUT = 12

  # exponential
  EXPONENTIAL_IN = 13
  EXPONENTIAL_OUT = 14
  EXPONENTIAL_IN_OUT = 15

  # sine
  SINE_IN = 16
  SINE_OUT = 17
  SINE_IN_OUT = 18

  # circular
  CIRCULAR_IN = 19
  CIRCULAR_OUT = 20
  CIRCULAR_IN_OUT = 21

  # elastic
  ELASTIC_IN = 22
  ELASTIC_OUT = 23
  ELASTIC_IN_OUT = 24

  # back
  BACK_IN = 25
  BACK_OUT = 26
  BACK_IN_OUT = 27

  # bounce
  BOUNCE_IN = 28
  BOUNCE_OUT = 29
  BOUNCE_IN_OUT = 30

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
