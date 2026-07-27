# ENGINE native=Sheet ruby=Sheet

class Sheet
  include UniqueHandle

  attr_reader :atlas
  def to_s = "Sheet(#{@atlas.path}, size: #{size})"
end
