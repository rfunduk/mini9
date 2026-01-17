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
    messages.each { |msg| @subs[msg] << callback }
    -> { $event_queue.unsubscribe(messages, callback) }
  end

  def unsubscribe(messages, callback)
    messages = [messages] if !messages.is_a?(Array)
    messages.each { |msg| @subs[msg].delete(callback) }
  end

  def process_events
    self.pop.tap do |e|
      @subs[e.message].each do |cb|
        cb.parameters.length == 0 ? cb.call() : cb.call(e)
      end
      event(e)
    end until self.empty?
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
