# ENGINE native=Oval ruby=Oval

class Oval
  undef_method :clone
  def dup = oval(pos, size)

  def to_s = "Oval(#{x}, #{y}, w=#{w}, h=#{h})"
  alias_method :inspect, :to_s
end
