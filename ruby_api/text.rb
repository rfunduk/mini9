# ENGINE native=Text ruby=Text

class Text
  include ValueShape
  def dup = text(str, font)

  def to_s = "Text(#{str.inspect})"
end
