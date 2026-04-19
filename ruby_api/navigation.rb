# ENGINE native=Navigator ruby=Navigator

class Navigator
  undef_method :clone
  def to_s = "Navigator(#{path_count} waypoints)"
  alias_method :inspect, :to_s
end
