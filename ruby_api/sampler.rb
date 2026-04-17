# ENGINE native=Sampler ruby=Sampler

class Sampler
  def to_s = "Sampler(#{lo}..#{hi})"
  alias_method :inspect, :to_s
end
