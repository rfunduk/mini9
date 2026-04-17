# ENGINE native=Anim ruby=Anim

class Anim
  undef_method :dup, :clone

  LOOP = 0
  ONCE = 1
  PING_PONG = 2
end
