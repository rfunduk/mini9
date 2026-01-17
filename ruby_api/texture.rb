# ENGINE native=Texture ruby=Texture

class Texture
  attr_reader :path
  def to_s = "Texture(#{path}, #{size || "<pending>"})"
  alias_method :inspect, :to_s
end
