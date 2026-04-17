class Numeric
  def move_toward(target, delta); end
  def lerp(target, weight); end
  def zero_approx?(epsilon = 1e-5); end
  def equal_approx?(other); end
  def sign; end
  def clamp(min, max); end
  def wrapf(min, max); end

  # convert degrees to radians
  def to_rad = self * Math::PI / 180

  # convert radians to degrees
  def to_deg = self * 180 / Math::PI
end
