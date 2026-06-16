# ENGINE native=Sound ruby=Sound

class Sound
  include NativeHandle

  attr_reader :path
  def to_s = "Sound(#{path})"
end
