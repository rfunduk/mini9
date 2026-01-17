# ENGINE native=Collision_Info ruby=CollisionInfo

class CollisionInfo
  def to_s
    "CollisionInfo(point: #{point}, normal: #{normal}, t: #{t}, body: #{body})"
  end
end
