# ENGINE native=rl.Vector2 ruby=Vector2

class Vector2
  ZERO = v2(0).freeze
  ONE = v2(1).freeze

  UP = N = v2(0, -1).freeze
  DOWN = S = v2(0, 1).freeze
  LEFT = W = v2(-1, 0).freeze
  RIGHT = E = v2(1, 0).freeze

  UP_LEFT = NW = v2(-1, -1).freeze
  UP_RIGHT = NE = v2(1, -1).freeze
  DOWN_LEFT = SW = v2(-1, 1).freeze
  DOWN_RIGHT = SE = v2(1, 1).freeze

  CARDINALS = [N, E, S, W].freeze
  COMPASS = [N, NE, E, SE, S, SW, W, NW].freeze

  include ValueShape
  def dup = v2(x, y)

  def xx = v2(x, x)
  def yy = v2(y, y)
  def yx = v2(y, x)

  def *(other) = other.is_a?(Numeric) ? _multiply_scalar(other.to_f) : _multiply(other)
  def /(other) = other.is_a?(Numeric) ? _divide_scalar(other.to_f) : _divide(other)
  def ==(other) = other.is_a?(self.class) ? x == other.x && y == other.y : false

  def to_s = "Vector2(#{x}, #{y})"
end
