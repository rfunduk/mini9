# ENGINE native=rl.Rectangle ruby=Rect

class Rect
  def clone = rect(pos, size)

  def to_s = "Rect(#{x}, #{y}, #{w}, #{h})"
  alias_method :inspect, :to_s
end
