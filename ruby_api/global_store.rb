class GlobalStore
  def method_missing(name, *args)
    name_str = name.to_s
    if name_str.end_with?("=")
      key = name_str[0..-2].to_sym
      # log("Defining global `#{key}`")
      instance_variable_set("@#{key}", args[0])
      define_singleton_method(key) { instance_variable_get("@#{key}") }
      define_singleton_method("#{key}=") { |v| instance_variable_set("@#{key}", v) }
    else
      super
    end
  end
end
