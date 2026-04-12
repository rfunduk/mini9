# convenience storage to avoid ugly $globals
def g = $g ||= GlobalStore.new

# default palette — predefined so the simplest games can use P.red etc.
# without setup. Independent copy of Palette::DEFAULT so `P.replace(...)`
# can't mutate the shared default. Override with `P.replace(palette("..."))`.
P = Palette::DEFAULT.dup

# add try method to all objects for safe navigation
class Object
  def try(method_name, *args, &block)
    return nil if self.nil?
    return nil unless self.respond_to?(method_name)
    send(method_name, *args, &block)
  end
end
