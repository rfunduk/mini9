# ENGINE native=Shake_Instance ruby=Shake

class Shake
  # called when shake(duration, frequency, amplitude) is invoked
  # duration: time in seconds (float)
  # frequency: samples per second (float)
  # amplitude: maximum displacement (float)
  def shake(duration, frequency, amplitude); end # this calls the native Odin implementation

  # returns the current shake offset as Vector2
  # automatically applies decay and interpolation
  def offset; end # this calls the native Odin implementation
end
