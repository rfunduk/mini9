# convenience storage to avoid ugly $globals
def g = $g ||= GlobalStore.new

# add try method to all objects for safe navigation
class Object
  def try(method_name, *args, &block)
    return nil if self.nil?
    return nil unless self.respond_to?(method_name)
    send(method_name, *args, &block)
  end
end
