# ENGINE native=Poly ruby=Poly

class Poly
  undef_method :clone
  def dup = poly(verts)

  def to_s = "Poly(#{count} verts)"
  alias_method :inspect, :to_s
end
