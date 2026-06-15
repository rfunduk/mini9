class EventQueue
  def initialize
    @events = []
    @subs = Hash.new { |h,k| h[k] = [] }
  end

  def push(event) = @events.push(event)
  def each = @events.each { |event| yield event }
  def pop = @events.shift
  def clear = @events.clear
  def size = @events.size
  def empty? = @events.empty?
  def any? = !empty?

  def subscribe(messages, callback)
    messages = [messages] if !messages.is_a?(Array)
    arity = callback.parameters.length  # Cache arity once at subscribe time
    sub = { cb: callback, arity: arity }
    messages.each { |msg| @subs[msg] << sub }
    -> { $event_queue.unsubscribe(messages, sub) }
  end

  def unsubscribe(messages, sub)
    messages = [messages] if !messages.is_a?(Array)
    messages.each { |msg| @subs[msg].delete(sub) }
  end

  def process_events
    until self.empty?
      e = self.pop
      @subs[e.message].each do |sub|
        sub[:arity] == 0 ? sub[:cb].call : sub[:cb].call(e)
      end
      event(e)
    end
  end
end

class CustomEvent
  attr_reader :message, :data

  def initialize(message, data = nil)
    @message = message
    @data = data
  end

  def to_s
    "CustomEvent(#{@message}, #{@data})"
  end
end

$event_queue = EventQueue.new

def dispatch(...) = $event_queue.push(CustomEvent.new(...))
def subscribe(...) = $event_queue.subscribe(...)
def unsubscribe(...) = $event_queue.unsubscribe(...)

# default impl of event handler if user doesnt do it
def event(e) = nil
