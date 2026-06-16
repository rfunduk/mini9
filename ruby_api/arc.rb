# ENGINE native=Arc ruby=Arc

class Arc
  include ValueShape
  def dup = arc(x, y, r, start, sweep)

  def to_s = "Arc(#{x}, #{y}, r=#{r}, start=#{start}, sweep=#{sweep})"
end
