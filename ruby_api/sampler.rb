# ENGINE native=Sampler ruby=Sampler

class Sampler
  include ValueShape
  def dup = sampler(lo, hi)

  def to_s = "Sampler(#{lo}..#{hi})"
end
