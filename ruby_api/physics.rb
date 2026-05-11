class Hit
  attr_reader :point, :normal, :fraction, :collider

  def initialize(point, normal, fraction, collider)
    @point = point
    @normal = normal
    @fraction = fraction
    @collider = collider
  end

  def to_s = "Hit(point=#{point}, normal=#{normal}, fraction=#{fraction.round(3)}, collider=#{collider})"
  alias_method :inspect, :to_s
end
