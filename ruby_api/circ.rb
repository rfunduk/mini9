# ENGINE native=Circ ruby=Circ

class Circ
  include ValueShape
  def dup = circ(x, y, r)

  def to_s = "Circ(#{x}, #{y}, r=#{r})"
end
