# ENGINE native=rl.Font ruby=Font

class Font
  include NativeHandle

  def to_s = "Font(#{name}, #{size})"
end
