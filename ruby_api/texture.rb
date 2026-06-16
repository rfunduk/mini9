# ENGINE native=Texture ruby=Texture

class Texture
  include NativeHandle

  attr_reader :path
  def to_s = "Texture(#{path}, #{size || "<pending>"})"
end
