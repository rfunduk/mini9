# ENGINE native=Music ruby=Music

class Music
  include NativeHandle

  attr_reader :path

  def play(volume: 1.0, loop: true, fade_in: 0.0); end
  def autoplay; end
  def pause(fade_out: 0.0); end
  def stop(fade_out: 0.0); end
  def playing?; end
  def looping?; end
  def volume; end
  def volume=; end
  def pitch; end
  def pitch=; end
  def fade_time; end

  def to_s = "Music(#{path})"
end
