# ENGINE native=Sprite ruby=Sprite

class Sprite
  undef_method :dup, :clone

  attr_reader :atlas
  def to_s = "Sprite(#{@atlas.path}, size: #{size}, frame: #{frame}, fliph: #{fliph}, flipv: #{flipv})"

  def flipv=(yn); _set_flip(nil, yn); yn; end
  def fliph=(yn); _set_flip(yn, nil); yn; end
end
