# ENGINE native=Sound ruby=Sound

class Sound
  attr_reader :path
  def to_s = "Sound(#{path})"
  alias_method :inspect, :to_s
end
