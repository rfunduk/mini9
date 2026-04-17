# ENGINE native=Particles_Instance ruby=Particles

class Particles
  undef_method :dup, :clone

  def to_s = "Particles(#{count}/#{max})"
  alias_method :inspect, :to_s
end
