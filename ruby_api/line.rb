# ENGINE native=Line ruby=Line

class Line
  include ValueShape
  def dup = line(a, b)

  def to_s = "Line(#{a} → #{b})"
end
