# ENGINE native=Body ruby=Body
# ENGINE native=Body_Spec ruby=BodySpec

class Body
  include NativeHandle

  def to_s = "Body(#{type}, shape: #{shape}#{sensor? ? ', sensor' : ''}#{spin? ? ', spin' : ''})"
end

class BodySpec
  include NativeHandle

  def to_s = "BodySpec"
end
