# ENGINE native=rl.Rectangle ruby=Rect

class Rect
  include ValueShape
  def dup = rect(x, y, w, h)

  def deflate(*args) = inflate(*args.map { |a| -a })

  def to_s = "Rect(#{x}, #{y}, #{w}, #{h})"
end
