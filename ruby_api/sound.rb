# ENGINE native=Sound ruby=Sound

class Sound
  undef_method :dup, :clone

  attr_reader :path
  def to_s = "Sound(#{path})"
  alias_method :inspect, :to_s
end
