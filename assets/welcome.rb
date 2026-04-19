# Mini9 welcome screen when no game loaded

title("mini9 — no game loaded")
resolution(320, 180)
fps(60)

SNIPPET_BOX = rect(v2(24, 58), v2(272, 76))

# token-based syntax highlighting. each line is an array of [text, color]
# pairs which we draw left-to-right, advancing x by text.measure.x. that
# gives us correct kerning on the variable-width pixel fonts without any
# manual measurement.
SNIPPET = [
  [['title',      P.blue],
   ['(',          P.white],
   ['"My Game"',  P.green],
   [')',          P.white]],

  [['def ',       P.magenta],
   ['update',     P.yellow],
   ['(dt)',       P.white]],

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
   ['v2',         P.blue],
   ['(10, 10), ', P.white],
   ['Font',       P.peach],
   ['::',         P.white],
   ['SMALL',      P.peach],
   [')',          P.white]],

  [['end',        P.magenta]],
]

def update(dt)
  quit if pressed?(:escape)
end

def draw
  clear(P.dark_blue)

  # bouncing ball — shows rendering and the update loop are alive
  t = time
  bx = 160 + Math.sin(t * 1.4) * 120
  by = 152 + (Math.sin(t * 4.2).abs * -8)
  line(v2(40, 156), v2(280, 156)).draw(color: P.light_gray)
  circ(v2(bx, by), 4).draw(filled: true, color: P.yellow)
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
