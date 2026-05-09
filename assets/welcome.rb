# Mini9 welcome screen when no game loaded

resolution(320, 180)
fps(60)

SNIPPET_BOX = rect(v2(24, 58), v2(272, 66))

# token-based syntax highlighting. each line is an array of [text, color]
# pairs which we draw left-to-right, advancing x by text.measure.x. that
# gives us correct kerning on the variable-width pixel fonts without any
# manual measurement.
SNIPPET = [
  [['def ',       P.magenta],
   ['update',     P.yellow]],

  [['    quit ',  P.blue],
   ['if ',        P.magenta],
   ['pressed?',   P.blue],
   ['(',          P.white],
   [':escape',    P.orange],
   [')',          P.white]],

  [['end',        P.magenta]],

  [['def ',       P.magenta],
   ['draw',       P.yellow]],

  [['    text',   P.blue],
   ['(',          P.white],
   ['"hi"',       P.green],
   [', ',         P.white],
   ['Font',       P.peach],
   ['::',         P.white],
   ['SMALL',      P.peach],
   [').draw(',    P.white],
   ['offset:',    P.orange],
   [' v2',        P.blue],
   ['(10)',       P.white]],

  [['end',        P.magenta]],
]

g.ball = v2()

TRAIL = particles(
  max: 100,
  rate: 50,
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
  text("MINI9", Font::LARGE).draw(offset: v2(160, 12), align: Text::CENTER)
  text("no main.rb found in target directory", Font::SMALL).draw(offset: v2(160, 32), color: P.light_gray, align: Text::CENTER)
  text("create one, like this:", Font::SMALL).draw(offset: v2(160, 40), color: P.light_gray, align: Text::CENTER)

  # snippet box
  SNIPPET_BOX.draw(filled: true, color: P.black)
  SNIPPET_BOX.draw(color: P.blue)

  draw_snippet(SNIPPET_BOX.pos + v2(8))

  text("press ESC to quit", Font::SMALL).draw(offset: v2(160, 168), align: Text::CENTER)
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
