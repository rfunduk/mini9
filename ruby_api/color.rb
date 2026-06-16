# ENGINE native=rl.Color ruby=Color

class Color
  include ValueShape
  def dup = color(r, g, b, a)

  def to_s = "Color(#{r}, #{g}, #{b}, #{a})"
end

# intelligent color function that handles multiple formats:
# color(r, g, b, a=255) - integer values 0-255
# color(0.5, 0.8, 0.2) - normalized values 0-1.0
# color("#FF0000") or color("FF0000") - hex strings
def color(*args)
  case args.size
  when 1
    _color_hex(args[0])
  when 3, 4
    r, g, b = args[0], args[1], args[2]
    if r.is_a?(Float) && r <= 1.0 && g.is_a?(Float) && g <= 1.0 && b.is_a?(Float) && b <= 1.0
      a = args.size == 4 ? args[3] : 1.0
      _color_normalized(r, g, b, a)
    else
      a = args.size == 4 ? args[3] : 255
      _color_int(r, g, b, a)
    end
  else
    raise ArgumentError, "color() expects 1, 3, or 4 arguments, got #{args.size}"
  end
end
