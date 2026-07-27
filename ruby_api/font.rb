# ENGINE native=rl.Font ruby=Font

class Font
  include UniqueHandle

  def to_s = "Font(#{name}, #{size})"
end
