# ENGINE native=Particles_Instance ruby=Particles

class Particles
  def to_s = "Particles(#{count}/#{max})"
  alias_method :inspect, :to_s
end
