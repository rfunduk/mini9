# ENGINE native=Circ ruby=Circ

class Circ
  undef_method :clone
  def dup = circ(x, y, r)

  def to_s = "Circ(#{x}, #{y}, r=#{r})"
  alias_method :inspect, :to_s
end
