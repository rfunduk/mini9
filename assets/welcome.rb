# welcome screen when no game loaded

resolution(320, 180)

class Array
  def i = self.tap { _1[0][0] = "    #{_1[0][0]}" }
end

class String
  %w{ magenta yellow blue white orange peach green red }.each do |c|
    define_method(:"#{c[0]}") { [self, P.send(c.to_sym)] }
  end
end

SNIPPET_BOX = rect(v2(24, 58), v2(272, 66))

SNIPPET = [
  ['def '.m, 'update'.y],
    ['quit '.b, 'if '.m, 'pressed?'.b, '('.w, ':escape'.o, ')'.w].i,
  ['end'.m],

  ['def '.m, 'draw'.y],
    ['text'.b, '('.w, '"hi"'.g, ', '.w, 'Font'.p, '::'.w, 'SMALL'.p, ').'.w,
      'draw'.b, '('.w, 'offset: '.o, 'v2'.b, '('.w, '10'.p, '))'.w].i,
  ['end'.m],
]

g.ball = v2()

TRAIL = particles(
  max: 120,
  rate: 60,
  lifetime: 4.5,
  pos: v2(0),
  accel: v2(0, 5),
  shape: :pixel,
  color: range(P.pink, color(0,0,0,0), 8),
  start: false
)

def update
  quit if pressed?(:escape)

  g.ball = v2(
    160 + Math.sin(time * 1.4) * 120,
    152 + (Math.sin(time * 4.2).abs * -8)
  )
  TRAIL.pos = circ(g.ball, 2)
  TRAIL.start
end

def draw
  clear(P.dark_blue)
  TRAIL.draw
  line(v2(40, 156), v2(280, 156)).draw(color: P.light_gray)
  rect(v2(30, 157), v2(280, 156)).draw(color: P.dark_blue, filled: true)
  circ(g.ball, 5).draw(filled: true, color: P.yellow)
end

def ui
  # title
  text("MINI9", Font::LARGE).tap do |t|
    t.draw(offset: v2(160 - t.measure.x/2, 12))
  end
  text("no main.rb found in target directory", Font::SMALL).tap do |t|
    t.draw(offset: v2(160 - t.measure.x/2, 32), color: P.light_gray)
  end
  text("create one, like this:", Font::SMALL).tap do |t|
    t.draw(offset: v2(160 - t.measure.x/2, 40), color: P.light_gray)
  end

  # snippet box
  SNIPPET_BOX.draw(filled: true, color: P.black)
  SNIPPET_BOX.draw(color: P.blue)

  draw_snippet(SNIPPET_BOX.pos + v2(8))

  text("press ESC to quit", Font::SMALL).tap do |t|
    t.draw(offset: v2(160 - t.measure.x/2, 168))
  end
end

def draw_snippet(origin)
  line_h = 9
  SNIPPET.each_with_index do |tokens, row|
    cx = origin.x
    tokens.each do |str, color|
      pos = v2(cx, origin.y + row * line_h)
      t = text(str, Font::SMALL)
      t.draw(offset: pos, color: color)
      cx += t.measure.x + 2
    end
  end
end
