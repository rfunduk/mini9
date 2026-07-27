# ENGINE native=Texture ruby=Texture

class Texture
  include UniqueHandle

  attr_reader :path
  def to_s = "Texture(#{path}, #{size || "<pending>"})"
end
