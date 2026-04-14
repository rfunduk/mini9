module Easing
  LINEAR = 0

  QUADRATIC_IN = 1
  QUADRATIC_OUT = 2
  QUADRATIC_IN_OUT = 3

  CUBIC_IN = 4
  CUBIC_OUT = 5
  CUBIC_IN_OUT = 6

  QUARTIC_IN = 7
  QUARTIC_OUT = 8
  QUARTIC_IN_OUT = 9

  QUINTIC_IN = 10
  QUINTIC_OUT = 11
  QUINTIC_IN_OUT = 12

  SINE_IN = 13
  SINE_OUT = 14
  SINE_IN_OUT = 15

  CIRCULAR_IN = 16
  CIRCULAR_OUT = 17
  CIRCULAR_IN_OUT = 18

  EXPONENTIAL_IN = 19
  EXPONENTIAL_OUT = 20
  EXPONENTIAL_IN_OUT = 21

  ELASTIC_IN = 22
  ELASTIC_OUT = 23
  ELASTIC_IN_OUT = 24

  BACK_IN = 25
  BACK_OUT = 26
  BACK_IN_OUT = 27

  BOUNCE_IN = 28
  BOUNCE_OUT = 29
  BOUNCE_IN_OUT = 30

  # implemented in native code
  # returns eased value of t (0.0..1.0) under the given easing
  def self.at(t, easing = LINEAR); end
end

# count >= 2; returns `count` floats from `from` to `to` with easing applied.
# first == from, last == to exactly.
def range(from, to, count, easing: Easing::LINEAR)
  raise ArgumentError, "range count must be >= 2 (got #{count})" if count < 2

  from = from.to_f
  to = to.to_f
  span = to - from
  last = count - 1
  result = Array.new(count)
  i = 0
  while i < count
    if i == 0
      result[i] = from
    elsif i == last
      result[i] = to
    else
      t = i.to_f / last
      result[i] = from + span * Easing.at(t, easing)
    end
    i += 1
  end
  result
end
