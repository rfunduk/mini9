# ENGINE native=Particles_Instance ruby=Particles

class Particles
  include NativeHandle

  def to_s = "Particles(#{count}/#{max})"
end
