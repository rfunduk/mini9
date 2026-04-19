# ENGINE native=Line ruby=Line

class Line
  undef_method :clone
  def dup = line(a, b)

  def to_s = "Line(#{a} → #{b})"
  alias_method :inspect, :to_s
end
