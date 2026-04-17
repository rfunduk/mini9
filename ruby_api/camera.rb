# ENGINE native=Camera_Instance ruby=Camera

class Camera
  undef_method :dup, :clone

  # camera properties are implemented in native code
  def active; end
  def active=(value); end

  def target; end
  def target=(value); end

  def zoom; end
  def zoom=(value); end

  def offset; end
  def offset=(value); end

  def reset(target: true, zoom: true); end

  def to_s = "Camera(#{'in' unless active}active, target: #{target}, zoom: #{zoom}, offset: #{offset})"
  alias_method :inspect, :to_s
end
