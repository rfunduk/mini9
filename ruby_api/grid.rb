# ENGINE native=Grid_Instance ruby=Grid

class Grid
  include Enumerable

  # Core methods implemented in Odin:
  def dimensions; end
  def length; end
  def type; end
  def [](i); end
  def []=(i, val); end
  def each(&blk); end
  def update(updates); end

  def clear
    length.times { |i| self[i] = falsy }
  end

  def any?
    each { |el| return true if el != falsy }
    false
  end

  def to_s = "Grid(#{dimensions}, #{type})"
  alias_method :inspect, :to_s

  private

  def falsy
    case type
    when :bool then false
    when :int then 0
    when :float then 0.0
    else nil
    end
  end
end
