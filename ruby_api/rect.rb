# ENGINE native=rl.Rectangle ruby=Rect

class Rect
  undef_method :clone
  def dup = rect(x, y, w, h)

  def deflate(*args) = inflate(*args.map { |a| -a })

  def to_s = "Rect(#{x}, #{y}, #{w}, #{h})"
  alias_method :inspect, :to_s
end
