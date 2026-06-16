# ENGINE native=Palette ruby=Palette

class Palette
  include ValueShape

  def to_s = "Palette(path: #{path}, count: #{count})"

  def replace(other)
    raise TypeError, "expected Palette" unless other.is_a?(Palette)
    __do_replace(other)
    self
  end

  # Called from native after construction or replacement. The closures over
  # `color` are what keep the color values alive once native drops its
  # temporary gc_register protection.
  def install_color_methods
    @__color_method_names = []
    __color_pairs.each do |name, color|
      define_singleton_method(name) { color }
      @__color_method_names << name
    end
    self
  end

  def uninstall_color_methods
    return self unless @__color_method_names
    sc = singleton_class
    @__color_method_names.each { |name| sc.send(:remove_method, name) }
    @__color_method_names = nil
    self
  end
end
