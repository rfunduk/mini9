# ENGINE native=Oval ruby=Oval

class Oval
  include ValueShape
  def dup = oval(pos, size)

  def to_s = "Oval(#{x}, #{y}, w=#{w}, h=#{h})"
end
