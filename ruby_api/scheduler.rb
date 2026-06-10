# Cooperative tasks. Long-running game work (AI search, procedural gen) split
# across frames to avoid blocking rendering

class Task
  attr_reader :result

  def initialize(check_every: 1, &blk)
    raise ArgumentError, "task requires a block" unless blk
    @check_every = check_every
    @counter = 0
    @deadline = 0.0
    @done = false
    @cancelled = false
    @result = nil
    @on_done = nil
    @fiber = Fiber.new do
      @result = blk.call
      @done = true
    end
  end

  def done? = @done
  def cancelled? = @cancelled

  # Stop the task. The fiber is abandoned mid-flight (suspended at its last
  # `coop`) and GC'd — no unwinding, so don't hold resources that need cleanup
  # across a `coop`. `result`/`on_done` never fire. For "keep the best so far",
  # have the block stash progress in your own var; read it after cancelling.
  def cancel
    @cancelled = true
    self
  end

  # Terminal either way — drives scheduler eviction.
  def dead? = @done || @cancelled

  # Register a completion callback. Fires once, in `tick`, the frame the task
  # finishes. If the task is already done, fire immediately.
  def on_done(&blk)
    @on_done = blk
    blk.call(@result) if @done && blk
    self
  end

  # Resume one slice. Driven by the scheduler, not the author.
  def step(deadline)
    return if self.dead?
    @deadline = deadline
    @fiber.resume
    @on_done.call(@result) if @done && @on_done
  end

  # Checkpoint body. Counter+modulo is the fast path; the clock read and
  # deadline compare only fire every Nth call, so authors can sprinkle freely.
  def checkpoint
    @counter += 1
    return true unless (@counter % @check_every).zero?
    Fiber.yield if walltime >= @deadline
    true
  end
end

class Scheduler
  def initialize
    @tasks = []
    @current = nil
  end

  def add(task) = task.tap { @tasks << _1 }

  # One slice per task per frame against a shared deadline. Completed tasks
  # drop out after the pass. `@current` lets `coop` find the running task.
  def tick(deadline)
    return if @tasks.empty?
    @tasks.each do |t|
      @current = t
      t.step(deadline)
    end
    @current = nil
    @tasks.reject!(&:dead?)
  end

  def coop = @current&.checkpoint
end

$tasks = Scheduler.new

def task(check_every: 1, &blk) = $tasks.add(Task.new(check_every: check_every, &blk))

# Author-facing checkpoint. Delegates to whichever task is currently resuming.
def coop = $tasks.coop
