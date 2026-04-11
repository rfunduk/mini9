# Mini9 welcome screen when no game loaded

title("mini9 — no game loaded")
resolution(320, 180)
fps(60)

P = Palette::DEFAULT

# token-based syntax highlighting. each line is an array of [text, color]
# pairs which we draw left-to-right, advancing x by text_size(...).x. that
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
  line(v2(40, 156), v2(280, 156), color: P.light_gray)
  circle(v2(bx, by), 4, filled: true, color: P.yellow)
end

def ui
  # title
  text("MINI9", v2(160, 12), Font::LARGE, align: Text::CENTER)
  text("no main.rb found in target directory", v2(160, 32), Font::SMALL, color: P.light_gray, align: Text::CENTER)
  text("create one, like this:", v2(160, 40), Font::SMALL, color: P.light_gray, align: Text::CENTER)

  # snippet box
  box = rect(24, 58, 272, 76)
  rectangle(box, filled: true, color: P.black)
  rectangle(box, color: P.blue)

  draw_snippet(box.pos + v2(8))

  text("press ESC to quit", v2(160, 168), Font::SMALL, align: Text::CENTER)
end

def draw_snippet(origin)
  line_h = 9
  SNIPPET.each_with_index do |tokens, row|
    cx = origin.x
    tokens.each do |str, color|
      pos = v2(cx, origin.y + row * line_h)
      text(str, pos, Font::SMALL, color: color)
      cx += text_size(str, Font::SMALL).x + 2
    end
  end
end
