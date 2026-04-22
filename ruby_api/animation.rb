# ENGINE native=Anim ruby=Anim

class Anim
  undef_method :dup, :clone

  LOOP = 0
  ONCE = 1
  PING_PONG = 2

  MODE_NAMES = { LOOP => "loop", ONCE => "once", PING_PONG => "ping_pong" }.freeze

  def to_s
    count = values.length
    dir = direction >= 0 ? "+#{direction}" : direction.to_s
    "#<Anim #{MODE_NAMES[mode] || mode} #{index}/#{count - 1}=#{current.inspect} @#{interval}s dir=#{dir}>"
  end

  alias_method :inspect, :to_s
end
