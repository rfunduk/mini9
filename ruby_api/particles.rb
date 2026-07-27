# ENGINE native=Particles_Instance ruby=Particles

class Particles
  include UniqueHandle

  def to_s = "Particles(#{count}/#{max})"
end
