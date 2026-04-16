# ENGINE native=Circ ruby=Circ

class Circ
  def to_s = "Circ(#{x}, #{y}, r=#{r})"
  alias_method :inspect, :to_s
end
