# ENGINE native=Navigator ruby=Navigator

class Navigator
  include Attachable
  include ValueShape
  def to_s = "Navigator(#{path_count} waypoints)"
end
