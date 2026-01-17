# TODO, make this a native system

class Anim
  LOOP = :loop
  ONCE = :once
  PING_PONG = :ping_pong

  attr_reader :current, :current_index, :values
  attr_accessor :direction, :mode

  alias_method :frames, :values
  alias_method :frame, :current
  alias_method :frame_index, :current_index

  def initialize(interval:, direction: +1, mode: LOOP, values: [])
    @mode = mode
    @original_interval = interval
    @original_direction = direction
    @values = values.to_a
    @value_count = values.size
    self.reset
  end

  def interval = @original_interval
  def interval=(n) @original_interval = n end

  def update(dt)
    @timer -= dt
    return if @timer > 0
    @timer += @original_interval

    case @mode
    when LOOP
      @current_index = (@current_index + @direction) % @value_count
    when PING_PONG
      @current_index += @direction
      if @current_index >= @value_count || @current_index < 0
        @direction = -@direction
        @current_index = @current_index.clamp(0, @value_count - 1)
      end
    when ONCE
      @current_index = (@current_index + @direction).clamp(0, @value_count - 1)
    end

    @current = @values[@current_index]
  end

  def reset
    @direction = @original_direction
    @timer = @original_interval
    @current_index = 0
    @current = @values[0]
  end

  def last_value? = direction > 0 ? @current_index == @value_count - 1 : @current_index == 0
  alias_method :last_frame?, :last_value?

  def progress
    return 0.0 if @value_count <= 1

    case @mode
    when LOOP, ONCE
      @current_index.to_f / (@value_count - 1)
    when PING_PONG
      # for ping-pong, progress goes 0->1->0 over the full cycle
      # not perfect but gives some indication of position
      if @direction > 0
        @current_index.to_f / (@value_count - 1)
      else
        1.0 - (@current_index.to_f / (@value_count - 1))
      end
    end
  end
end

def anim(interval:, direction: +1, mode: Anim::LOOP, frames: [])
  Anim.new(interval:, direction:, mode:, values: frames)
end
