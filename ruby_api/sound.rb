# ENGINE native=Sound ruby=Sound

class Sound
  include NativeHandle

  attr_reader :path

  def play(pitch: 1.0, volume: 1.0); end
  def pause(fade_out: 0.0); end
  def stop(fade_out: 0.0); end

  def to_s = "Sound(#{path})"
end
