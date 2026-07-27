# ENGINE native=Body ruby=Body
# ENGINE native=Body_Spec ruby=BodySpec

class Body
  include UniqueHandle

  def to_s = "Body(#{type}, shape: #{shape}#{sensor? ? ', sensor' : ''}#{spin? ? ', spin' : ''})"
end

class BodySpec
  include UniqueHandle

  def to_s = "BodySpec"
end
