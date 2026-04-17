# ENGINE native=rl.Font ruby=Font

class Font
  undef_method :dup, :clone

  def to_s = "Font(#{name}, #{size})"
  alias_method :inspect, :to_s
end
