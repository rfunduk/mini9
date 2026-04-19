# ENGINE native=Text ruby=Text

class Text
  undef_method :clone
  def dup = text(str, font)

  def to_s = "Text(#{str.inspect})"
  alias_method :inspect, :to_s
end
