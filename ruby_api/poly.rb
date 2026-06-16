# ENGINE native=Poly ruby=Poly

class Poly
  include ValueShape
  def dup = poly(verts)

  def to_s = "Poly(#{count} verts)"
end
