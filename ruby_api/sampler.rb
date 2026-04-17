# ENGINE native=Sampler ruby=Sampler

class Sampler
  undef_method :clone
  def dup = sampler(lo, hi)

  def to_s = "Sampler(#{lo}..#{hi})"
  alias_method :inspect, :to_s
end
