# ENGINE native=Palette ruby=Palette

class Palette
  attr_reader :path, :count, :colors
  def to_s = "Palette(path: #{path}, count: #{count}, colors: #{colors.map(&:to_s).join(', ')})"
  alias_method :inspect, :to_s

  private def setup(names, values)
    names.zip(values).each do |name, color|
      define_singleton_method(name, -> { color })
    end
  end
end
