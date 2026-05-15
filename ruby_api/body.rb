# ENGINE native=Body ruby=Body
# ENGINE native=Body_Spec ruby=BodySpec

class Body
  undef_method :dup, :clone

  def to_s = "Body(#{type}, shape: #{shape}#{sensor? ? ', sensor' : ''}#{spin? ? ', spin' : ''})"
  alias_method :inspect, :to_s
end

class BodySpec
  undef_method :dup, :clone

  def to_s = "BodySpec"
  alias_method :inspect, :to_s
end
