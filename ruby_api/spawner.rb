# Spawner — named, lifecycle-managed wrapper around `every` for
# repeatedly invoking a block at a configurable rate and burst count.
# Pure Ruby; no native backing. Follows Timer conventions: block's
# `this` arg is the parent GameObject (via `init(parent)`) or nil
# when standalone.

def spawner(rate:, count: 1, start: true, &block)
  raise ArgumentError, "spawner requires a block" unless block
  Spawner.new(rate: rate, count: count, start: start, block: block)
end

class Spawner
  undef_method :dup, :clone

  attr_accessor :rate, :count
  attr_reader :parent

  def initialize(rate:, count: 1, start: true, block:)
    @rate = rate
    @count = count
    @block = block
    @parent = nil
    @running = false
    @timer = nil
    @scheduled = nil
    self.start if start
  end

  def init(parent)
    @parent = parent
    self
  end

  def start
    return self if @running
    @running = true
    schedule
    self
  end

  def stop
    @running = false
    @timer&.cancel
    @timer = nil
    @scheduled = nil
    self
  end

  def running? = @running

  def fire!
    resolve_count.times { @block.call(@parent) }
    self
  end

  def to_s = "Spawner(rate: #{@rate}, count: #{@count}, running: #{@running})"
  alias_method :inspect, :to_s

  private

  def schedule
    return unless @running
    interval = resolve_interval
    @scheduled = interval
    @timer = every(interval) do |_this|
      resolve_count.times { @block.call(@parent) }
      if !fixed_rate? || resolve_interval != @scheduled
        @timer&.cancel
        @timer = nil
        schedule
      end
    end
  end

  def resolve_interval
    case @rate
    when Numeric then @rate.to_f
    when Range then sample_range(@rate)
    else raise ArgumentError, "spawner rate must be Numeric or Range (got #{@rate.class})"
    end
  end

  def resolve_count
    case @count
    when Integer then @count
    when Range then rand(@count)
    else @count.to_i
    end
  end

  def fixed_rate? = @rate.is_a?(Numeric)

  def sample_range(r)
    lo = r.first.to_f
    hi = r.last.to_f
    hi -= 1 if r.exclude_end? && hi > lo
    lo + rand * (hi - lo)
  end
end
