# ENGINE native=Arc ruby=Arc

class Arc
  undef_method :clone
  def dup = arc(x, y, r, start, sweep)

  def to_s = "Arc(#{x}, #{y}, r=#{r}, start=#{start}, sweep=#{sweep})"
  alias_method :inspect, :to_s
end
