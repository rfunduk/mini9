# Mini9

2D game framework. Ruby scripts on top of a native Odin/Raylib engine.

A minimum game is a single `main.rb` file:

```ruby
title("My Game")
resolution(320, 240)

def update(dt)
  quit if pressed?(:escape)
end

def draw
  clear(P.black)
  circ(v2(160, 120), 20).draw(color: P.red, filled: true)
end
```

`P` is predefined as a copy of `Palette::DEFAULT` — no setup needed for the built-in colors.

Run it: `mini9 /path/to/game/`.

See `API_CONVENTIONS.md` for the rules the API follows.

---

## Contents

- [Project Structure](#project-structure)
- [Game Callbacks](#game-callbacks)
- [Setup](#setup)
- [Drawing](#drawing)
- [Text & Fonts](#text--fonts)
- [Colors & Palettes](#colors--palettes)
- [Vectors](#vectors)
- [Shapes](#shapes)
- [Textures & Sprites](#textures--sprites)
- [Input](#input)
- [Sound](#sound)
- [Music](#music)
- [Animation](#animation)
- [Tweening](#tweening)
- [Particles](#particles)
- [Spawner](#spawner)
- [Timers](#timers)
- [Camera](#camera)
- [Screen Shake](#screen-shake)
- [Game Objects](#game-objects)
- [State Machines](#state-machines)
- [Collision/Physics](#collisionphysics)
- [Events](#events)
- [Numeric Helpers](#numeric-helpers)
- [Global Store](#global-store)
- [File Data](#file-data)
- [Save & Load](#save--load)
- [Debug & System](#debug--system)
- [Importing Code](#importing-code)
- [Cookbook](#cookbook)

---

## Project Structure

A game is a directory. The bare minimum is a single `main.rb`:

```
my_game/
└── main.rb
```

A typical layout adds assets and split-out code:

```
my_game/
├── main.rb              # entry point — required
├── metadata             # optional — title, packaging excludes
├── player.rb            # imported via import(:player)
├── enemy.rb
└── assets/
    ├── sprites/
    │   └── player.png
    ├── sounds/
    │   └── jump.ogg
    └── music/
        └── theme.ogg
```

Asset paths inside the code are relative to the game's root directory:

```ruby
PLAYER_TEX = texture("assets/sprites/player.png")
```

### `metadata`

Optional file at the game root, in SJSON (relaxed JSON):

```
title = "My Game"
exclude = ["**/*.aseprite", ".DS_Store", "notes.txt"]
```

| Key | Type | Notes |
|---|---|---|
| `title` | string | Window title. Overrides `title()` from `main.rb` when packaging |
| `exclude` | array of glob strings | Files to omit from `.rom` packaging |

### Running

```
mini9 path/to/my_game/        # run from a directory
mini9 path/to/my_game.rom     # run a packaged ROM
```

### Packaging

```
mini9 package --source my_game --output .          # → my_game.rom
mini9 package --web --source my_game --output .    # → my_game/ + index.html
```

The `--web` form produces a static site you can host anywhere.

---

## Game Callbacks

Define any of these top-level methods and the engine will call them each frame. All four are optional.

| Method | When called | Notes |
|---|---|---|
| `update(dt=nil)` | Each frame, before draw | `dt` is optional — declare it if you want delta time in seconds |
| `draw` | Each frame, inside camera transform | Render the world |
| `ui` | Each frame, outside camera transform | Render HUD/menus (no zoom, no camera offset) |
| `event(e)` | Once per dispatched custom event | `e` is a `CustomEvent` with `.message` and `.data` |

```ruby
def update(dt)
  PLAYER.move(dt)
end

def draw
  clear(P.black)
  PLAYER.draw
end

def ui
  text("Score: #{g.score}", Font::SMALL).draw(offset: v2(4))
end

def event(e)
  g.score += 100 if e.message == :coin_collected
end
```

---

## Setup

Call during load (before the first frame). Most setup functions can only be changed in the `INIT` phase — at script load time — and silently return current values afterward.

| Signature | Returns | Notes |
|---|---|---|
| `title(str)` | nil | Window title |
| `resolution(w, h=w)` | Vector2 | Internal render resolution. Window scales to fit |
| `fps(target)` | Integer | Target framerate. Minimum 5. INIT phase only |
| `fullscreen(yn=nil)` | bool | No args → current state. Not available on web |
| `cursor(yn=nil)` | bool | Show/hide OS cursor |
| `time` | Float | Seconds since game started |
| `quit` | nil | Exit the game |
| `web?` | bool | True if running in browser |
| `assert(yn, message=nil)` | nil | Raises `RuntimeError` if `yn` is falsy |

---

## Drawing

All drawing happens inside `draw` (world-space, camera-transformed) or `ui` (screen-space).

Every shape is an object you construct once, then render with `.draw(**opts)`. Construction is cheap and constructors live alongside the geometry types (see [Shapes](#shapes), [Vectors](#vectors), and [Text & Fonts](#text--fonts) for their non-drawing methods).

| Constructor | Shape | `.draw` options |
|---|---|---|
| `v2(x[, y])` | Vector2 (a single pixel) | `color:`, `offset:` |
| `line(to)` or `line(a, b)` | Line | `color:`, `thickness:`, `offset:`, `clip:` |
| `rect(...)` | Rect — see [Shapes](#shapes) for the 3 forms | `color:`, `filled:`, `thickness:`, `rounded:`, `offset:`, `clip:` |
| `circ(r)` / `circ(center, r)` / `circ(x, y, r)` | Circ | `color:`, `filled:`, `thickness:`, `offset:`, `clip:` |
| `oval(size)` or `oval(pos, size)` | Oval — `size` is v2(w_radius, h_radius) | `color:`, `filled:`, `offset:`, `clip:` |
| `poly(verts)` | Poly — `verts` is Array[Vector2], min 3 | `color:`, `filled:`, `thickness:`, `offset:`, `clip:` |
| `text(str, font)` | Text — see [Text & Fonts](#text--fonts) | `color:`, `outline:`, `align:`, `rotation:`, `scale:`, `spacing:`, `offset:` |

Plus the screen-clearing primitive:

| Signature | Returns | Notes |
|---|---|---|
| `clear(color)` | nil | Fills the screen. Safe to call in `draw` or once in setup |

**Shared draw options:**

- `color:` — default white
- `offset:` — a Vector2 added to the shape's native position before drawing. Lets you keep one shape constant and render it in many places
- `filled:` — fills the interior
- `thickness:` — outline stroke width in px
- `rounded:` — rectangle corner radius, 0–100 (percentage of the shorter edge)
- `clip:` — a `Rect` in coordinates relative to the shape's `pos` that scissors the draw to that region

```ruby
# construct once, draw many places
DOT  = circ(4)
LINE = line(v2(100, 0))

def draw
  clear(P.black)
  LINE.draw(offset: v2(10, 50), color: P.white, thickness: 2)
  DOT.draw(offset: v2(50), filled: true, color: P.red)
  rect(v2(10), v2(40, 20)).draw(filled: true, color: P.red, rounded: 30)
  poly([v2(0), v2(20, 0), v2(10, 20)]).draw(filled: true, color: P.yellow)
end
```

---

## Text & Fonts

Text is a shape like any other — construct with `text(str, font)`, render with `.draw(**opts)`. Call `.measure` to get rendered size without drawing.

| Signature | Returns | Notes |
|---|---|---|
| `text(str, font)` | Text | Both args required; `font` must be a Font |
| `t.str` | String | The stored string |
| `t.font` | Font | |
| `t.measure(scale: 1, spacing: 1)` | Vector2 | Rendered size without drawing |
| `t.draw(**opts)` | nil | See options below |
| `font(path, size=nil)` | Font | `size` required for TTF/OTF; not needed for `.png` bitmap fonts |

`t.draw` options: `offset:`, `align:` (`Text::LEFT`, `Text::CENTER`, `Text::RIGHT`), `rotation:`, `scale:`, `spacing:`, `color:`, `outline:`. `outline:` accepts a Color or `true` (black).

**Built-in fonts** (always available):

| Constant | Size |
|---|---|
| `Font::TINY` | 6px |
| `Font::SMALL` | 8px |
| `Font::MEDIUM` | 11px |
| `Font::LARGE` | 15px |

**Font instance methods:**

| Signature | Returns |
|---|---|
| `font.name` | String |
| `font.size` | Integer |

```ruby
text("Hello", Font::SMALL).draw(offset: v2(10), color: P.yellow)
MY_FONT = font("assets/pixel.ttf", 16)
title = text("Custom", MY_FONT)
title.draw(offset: v2(160, 30), align: Text::CENTER)
size = title.measure(scale: 2)
```

---

## Colors & Palettes

### `color`

```ruby
color(255, 128, 64)          # integer RGB (0-255)
color(255, 128, 64, 200)     # integer RGBA
color(0.5, 0.3, 0.8)         # normalized RGB (0.0-1.0)
color(0.5, 0.3, 0.8, 0.9)    # normalized RGBA
color("#FF8040")             # hex string
color("FF8040")              # hex without #
```

Auto-detects integer vs. normalized based on whether the first three args are Floats ≤ 1.0.

**Color instance methods:**

| Signature | Returns | Notes |
|---|---|---|
| `c.r` / `c.r = v` | Integer (0-255) | Also `g`, `b`, `a` |
| `c == other` | bool | |

### `palette`

Load a GIMP `.gpl` palette file. Colors become methods on the palette object, named after their entries in the file.

| Signature | Returns | Notes |
|---|---|---|
| `palette(path)` | Palette | Loads a `.gpl` file |
| `pal[name_or_index]` | Color | Lookup by name (string/symbol) or by integer index |
| `pal.count` | Integer | Number of colors |
| `pal.colors` | Array[Color] | All colors in file order |
| `pal.path` | String | Source path |
| `pal.dup` | Palette | Independent deep copy — mutating the copy never touches the original |
| `pal.replace(other)` | self | Swap this palette's contents with `other`'s. Mutates in place — every existing reference to `pal` sees the new colors |

**Built-in palette:** `Palette::DEFAULT`. 16 named colors:

| Name | RGB | | Name | RGB |
|---|---|---|---|---|
| `black` | 0, 0, 0 | | `red` | 237, 0, 24 |
| `white` | 255, 255, 255 | | `yellow` | 255, 225, 39 |
| `blue` | 38, 149, 240 | | `peach` | 255, 212, 184 |
| `dark_blue` | 22, 44, 102 | | `orange` | 227, 148, 0 |
| `green` | 0, 189, 28 | | `pink` | 255, 119, 168 |
| `dark_green` | 0, 115, 25 | | `purple` | 112, 77, 179 |
| `magenta` | 176, 40, 90 | | `brown` | 161, 76, 48 |
| `light_gray` | 143, 144, 148 | | `dark_gray` | 61, 59, 56 |

**`P`** is a predefined top-level constant — an independent copy of `Palette::DEFAULT`. Use it directly without any setup. To swap in a different palette without breaking existing references, use `P.replace(...)`:

```ruby
clear(P.black)
circ(v2(50), 10).draw(color: P.red, filled: true)

# swap to a custom palette — every later P.foo lookup uses the new colors
P.replace(palette("assets/pico8.gpl"))
clear(P.dark_blue)

# or load a separate palette under its own name
PICO = palette("assets/pico8.gpl")
rect(v2(0), v2(100)).draw(color: PICO.dark_blue, filled: true)
```

Color names come from the `.gpl` file's entries, lowercased (e.g. `effae6` from a hex-named palette becomes `pal.effae6`).

---

## Vectors

`v2(x, y)` is the universal 2D value. Most math is immutable (returns a new vector).

| Signature | Returns | Notes |
|---|---|---|
| `v2(x=0, y=x)` | Vector2 | `v2(5)` → `v2(5, 5)` |
| `v.x` / `v.x = n` | Float | Also `y`. Aliases: `w`/`h`, `left`/`top` |
| `v + other` | Vector2 | |
| `v - other` | Vector2 | |
| `-v` | Vector2 | Unary negate |
| `v * scalar_or_v2` | Vector2 | Scalar or componentwise |
| `v / scalar_or_v2` | Vector2 | Scalar or componentwise |
| `v == other` | bool | |
| `v.dup` | Vector2 | Fresh copy |
| `v.xx` / `v.yy` / `v.yx` | Vector2 | Swizzles |
| `v.floor` / `v.ceil` / `v.round` | Vector2 | |
| `v.abs` | Vector2 | |
| `v.sign` | Vector2 | Per-component -1/0/1 |
| `v.length` | Float | |
| `v.length_squared` | Float | Cheaper when you only need to compare |
| `v.normalized` | Vector2 | |
| `v.rotated(angle)` | Vector2 | Radians |
| `v.angle` | Float | Radians |
| `v.angle_to(other)` | Float | Radians |
| `v.dot(other)` | Float | |
| `v.distance_to(other)` | Float | |
| `v.direction_to(other)` | Vector2 | Normalized |
| `v.lerp(to, weight)` | Vector2 | |
| `v.move_toward(to, delta)` | Vector2 | |
| `v.clamp(min, max=nil)` | Vector2 | With one arg, clamps magnitude |
| `v.zero_approx?` | bool | |
| `v.equal_approx?(other)` | bool | |
| `v.grid_index(width, height=width, wrap: false)` | Integer or nil | Flatten to linear index |

**Constants:**

| Constant | Value |
|---|---|
| `Vector2::ZERO` | `v2(0)` |
| `Vector2::ONE` | `v2(1, 1)` |
| `Vector2::UP` / `N` | `v2(0, -1)` |
| `Vector2::DOWN` / `S` | `v2(0, 1)` |
| `Vector2::LEFT` / `W` | `v2(-1, 0)` |
| `Vector2::RIGHT` / `E` | `v2(1, 0)` |
| `Vector2::UP_LEFT` / `NW` | `v2(-1, -1)` |
| `Vector2::UP_RIGHT` / `NE` | `v2(1, -1)` |
| `Vector2::DOWN_LEFT` / `SW` | `v2(-1, 1)` |
| `Vector2::DOWN_RIGHT` / `SE` | `v2(1, 1)` |
| `Vector2::CARDINALS` | `[N, E, S, W]` |
| `Vector2::COMPASS` | `[N, NE, E, SE, S, SW, W, NW]` |

---

## Shapes

Every shape constructor returns a native object with instance methods listed below. All shapes also have `.draw(**opts)` — see [Drawing](#drawing) for the shared option set.

### Rect

| Signature | Returns | Notes |
|---|---|---|
| `rect(size)` | Rect | Positioned at origin |
| `rect(pos, size)` | Rect | |
| `rect(x, y, w, h)` | Rect | |
| `r.pos` | Vector2 | |
| `r.size` | Vector2 | |
| `r.x` / `r.x = n` | Float | Also `y`, `w`, `h` |
| `r.dup` | Rect | Fresh copy |
| `r.inflate(n)` | Rect | Grow uniformly by `n` on all sides |
| `r.inflate(v2)` | Rect | Grow by `v2.x` horizontally + `v2.y` vertically (per side) |
| `r.inflate(t, r, b, l)` | Rect | Per-side inflate |
| `r.deflate(n)` | Rect | Shrink uniformly by `n` on all sides |
| `r.deflate(v2)` | Rect | Shrink by `v2.x` horizontally + `v2.y` vertically (per side) |
| `r.deflate(t, r, b, l)` | Rect | Per-side deflate |
| `r.contains?(v2)` | bool | Point inside rect (edge-inclusive) |
| `r.sample_point` | Vector2 | Uniform random point inside rect |

### Circ

| Signature | Returns | Notes |
|---|---|---|
| `circ(radius)` | Circ | Centered at `v2(0)` |
| `circ(center, radius)` | Circ | `center` is Vector2 |
| `circ(x, y, radius)` | Circ | |
| `c.center` | Vector2 | |
| `c.x` / `c.y` / `c.r` / `c.radius` | Float | All assignable |
| `c.contains?(v2)` | bool | |
| `c.distance(v2)` | Float | |
| `c.overlaps?(other)` | bool | `other` is Circ or Rect |
| `c.sample_point` | Vector2 | Uniform random point inside disk |

### Line

| Signature | Returns | Notes |
|---|---|---|
| `line(to)` | Line | From `v2(0)` to `to` |
| `line(a, b)` | Line | Explicit endpoints |
| `l.a` / `l.b` | Vector2 | |
| `l.length` | Float | |
| `l.midpoint` | Vector2 | |
| `l.dup` | Line | Fresh copy |

### Oval

| Signature | Returns | Notes |
|---|---|---|
| `oval(size)` | Oval | Centered at `v2(0)`. `size` is v2(w_radius, h_radius) — half-axes |
| `oval(pos, size)` | Oval | Explicit center |
| `o.pos` / `o.size` | Vector2 | |
| `o.x` / `o.y` / `o.w` / `o.h` | Float | |
| `o.dup` | Oval | Fresh copy |

### Poly

| Signature | Returns | Notes |
|---|---|---|
| `poly(verts)` | Poly | `verts` is Array[Vector2], minimum 3 |
| `p.verts` | Array[Vector2] | |
| `p.count` | Integer | |
| `p.contains?(v2)` | bool | Ray-cast point-in-polygon |
| `p.dup` | Poly | Fresh copy |

---

## Textures & Sprites

### Textures

| Signature | Returns |
|---|---|
| `texture(path)` | Texture |
| `tex.size` | Vector2 |
| `tex.draw(pos, clip: nil)` | self |
| `tex.path` | String |

### Sprites

A `Sprite` is an animated region inside a `Texture` atlas.

```ruby
tex = texture("assets/player.png")
spr = sprite(tex, size: v2(16))   # 16x16 frames, auto-calculated frame count
spr.frame = 3
spr.fliph = true
spr.draw(v2(100))
```

| Signature | Returns | Notes |
|---|---|---|
| `sprite(tex, **opts)` | Sprite | |
| `s.draw(pos, clip: nil)` | self | |
| `s.size` / `s.size = v2` | Vector2 | Frame size |
| `s.frame` / `s.frame = n` | Integer | Wraps automatically |
| `s.frames` | Integer | Total frame count (auto-calculated from texture + size) |
| `s.fliph` / `s.fliph = yn` | bool | |
| `s.flipv` / `s.flipv = yn` | bool | |
| `s.rotation` / `s.rotation = r` | Float | Radians (use `n.to_rad` / `n.to_deg` to convert) |
| `s.offset` / `s.offset = v2` | Vector2 | Draw offset (pivot) |
| `s.scale` / `s.scale = v2` | Vector2 | |

`sprite()` options: `size:`, `frame:`, `frames:`, `fliph:`, `flipv:`, `rotation:`, `offset:`, `scale:`, `atlas:`.

---

## Input

All input is unified under symbols. Keyboard, mouse, and gamepad share the same API.

| Signature | Returns | Notes |
|---|---|---|
| `down?(sym, gamepad: nil)` | bool | Held this frame |
| `pressed?(sym, gamepad: nil)` | bool | Just pressed this frame |
| `released?(sym, gamepad: nil)` | bool | Just released this frame |
| `keys` | Array[Symbol] | Keys pressed this frame (text entry) |
| `get_axis(h, v, gamepad: nil)` | Vector2 | Normalized from 2 pairs of keys |
| `get_axis(horizontal:, vertical:, gamepad: nil)` | Vector2 | Kwarg form |
| `mouse(layer = :world)` | Vector2 | `:world` (camera-transformed) or `:ui`. Bare `mouse` defaults to `:world` |
| `gamepad?(id)` | bool | Is this gamepad connected |

**Input symbols** include `:a`–`:z`, `:0`–`:9`, `:space`, `:enter`, `:escape`, `:shift`, `:ctrl`, `:alt`, `:up`/`:down`/`:left`/`:right`, `:f1`–`:f12`, `:left_mouse`/`:right_mouse`/`:middle_mouse`, and gamepad buttons/axes like `:left_face_down`, `:left_x`, `:right_trigger`. For gamepad inputs, pass `gamepad: 0` (or other ID).

```ruby
quit if pressed?(:escape)
dir = get_axis(%i{a d}, %i{w s})
PLAYER.pos += dir * 100 * dt

if pressed?(:left_mouse)
  shoot_at(mouse)
end
```

---

## Sound

Short polyphonic sound effects — multiple instances can play simultaneously. Loaded from `.ogg`, `.wav`, etc.

| Signature | Returns | Notes |
|---|---|---|
| `sound(path, polyphony: 8)` | Sound | `polyphony` = max simultaneous instances |
| `s.play(volume: 1.0, pitch: 1.0)` | self | |
| `s.stop(fade_out: 0)` | self | |
| `s.pause(fade_out: 0)` | self | |
| `s.path` | String | |

```ruby
JUMP = sound("assets/jump.ogg")
JUMP.play(volume: 0.8, pitch: 1.2)
```

---

## Music

Single streaming audio source. Designed for looping background tracks.

| Signature | Returns | Notes |
|---|---|---|
| `music(path)` | Music | |
| `m.play(volume: 1.0, loop: true, fade_in: 0)` | self | |
| `m.stop(fade_out: 0)` | self | |
| `m.pause(fade_out: 0)` | self | |
| `m.autoplay` | self | Start playing as soon as audio system is ready |
| `m.playing?` | bool | |
| `m.looping?` | bool | |
| `m.volume` / `m.volume = v` | Float | |
| `m.fade_time` | Float | Remaining fade time |
| `m.path` | String | |

On web builds, audio is initialized on first user input (browser requirement). `autoplay` handles deferred loading automatically.

```ruby
BGM = music("assets/theme.ogg")
BGM.autoplay
```

---

## Animation

Frame-based animations that cycle through a set of values on a timer.

| Signature | Returns | Notes |
|---|---|---|
| `anim(interval:, values:, direction: 1, mode: Anim::LOOP)` | Anim | |
| `a.update(dt)` | nil | Call each frame |
| `a.reset` | nil | |
| `a.current` | any | Current value from `values` |
| `a.index` | Integer | Current index into `values` |
| `a.values` | Array | |
| `a.interval` / `a.interval = s` | Float | Seconds per frame |
| `a.direction` / `a.direction = d` | Integer | `1` or `-1` |
| `a.mode` / `a.mode = m` | Integer | `Anim::LOOP`, `Anim::ONCE`, `Anim::PING_PONG` |
| `a.progress` | Float | 0.0–1.0 |
| `a.last?` | bool | True on the terminal frame |

`values` can hold anything — sprite frame indices, colors, vectors, symbols. `current` returns whatever you put in.

```ruby
WALK = anim(interval: 0.1, values: [0, 1, 2, 3])

def update(dt)
  WALK.update(dt)
  PLAYER_SPRITE.frame = WALK.current
end
```

---

## Tweening

Time-based interpolation from one value to another, with easing. Works on Numerics and Vector2s.

| Signature | Returns | Notes |
|---|---|---|
| `tween(from, to, duration, delay: 0, easing: Easing::LINEAR) { \|value\| ... }` | Tween | Block fires every frame |
| `t.value` | Numeric/Vector2 | Current interpolated value |
| `t.running?` | bool | |
| `t.finished?` | bool | |
| `t.just_finished?` | bool | True for exactly one frame |
| `t.time_left` | Float | Seconds |
| `t.progress` | Float | 0.0–1.0 |
| `t.stop` | nil | |

**Easing constants** (all `Easing::*`):

`LINEAR`, plus `IN` / `OUT` / `IN_OUT` variants of: `QUADRATIC`, `CUBIC`, `QUARTIC`, `QUINTIC`, `SINE`, `CIRCULAR`, `EXPONENTIAL`, `ELASTIC`, `BACK`, `BOUNCE`. Total: 31 easings.

```ruby
tween(v2(0), v2(100, 50), 1.0, easing: Easing::CUBIC_OUT) do |pos|
  PLAYER.pos = pos
end
```

`ease(t, Easing::LINEAR)` returns the eased value of `t` (0.0–1.0). Useful standalone.

`range(from, to, count, easing: Easing::LINEAR)` returns an Array of `count` values from `from` to `to`, with easing applied. First and last entries are exactly `from` / `to`. `count` must be ≥ 2. Supports Numeric, Vector2, and Color — type is detected from `from`/`to` (both must match). Feed into `anim`'s `values:` for eased sequences, or pass directly to `particles` for curve-over-life:

```ruby
range(1.0, 0.0, 20)                 # Array of 20 Floats
range(v2(0), v2(100, 50), 10)       # Array of 10 Vector2s
range(P.yellow, P.red, 8)           # Array of 8 Colors (channel-lerped)
```

Concat ranges for piecewise curves — each segment's count controls its time weight:

```ruby
fade = anim(interval: 0.05, values: range(255, 0, 30, easing: Easing::CUBIC_OUT))

def update(dt)
  fade.update(dt)
  clear(color(0, 0, 0, fade.current))
end
```

---

## Particles

Native SOA particle system. Hundreds cheap, thousands OK. Auto-updated each tick; manual draw for user-controlled draw order.

### `particles`

```ruby
particles(
  max:,                # required Integer — ring buffer capacity
  rate:,               # required Numeric — particles/sec (0 = burst-only)
  lifetime:,           # required Numeric | sampler()
  pos:,                # required v2 | rect | circ | sampler(v2, v2)
  velocity: v2(0),     # v2 | sampler(v2, v2)
  accel: v2(0),        # v2 | sampler(v2, v2) | range(v2)
  drag: nil,           # Float (0..1) | range(Float) — drag amount per tick
  rotation: 0,         # Float radians | sampler(f, f)
  ang_vel: 0,          # Float radians/sec | sampler(f, f)
  ang_accel: 0,        # Float radians/sec² | sampler(f, f) | range(Float)
  ang_drag: nil,       # Float (0..1) | range(Float) — angular drag per tick
  shape: :pixel,       # :pixel | :rect | :circle | :line
  size: v2(1),         # v2 | range(Float) | range(v2)
  color: P.white,      # Color | range(Color)
  start: true,         # false to create paused
)
```

**Per-particle property values** — props accept several forms:

| Form | Meaning | Sampled |
|---|---|---|
| scalar (`v2`, `Float`, `Color`) | All particles share one value | once at construct |
| `sampler(lo, hi)` | Uniform random | per particle at spawn |
| `range(from, to, n)` | Curve-over-life — adjacent entries lerped by particle age | per particle per frame |

**`pos:` sources** — controls where particles spawn:

| Form | Behavior |
|---|---|
| `v2(x, y)` | Fixed point |
| `rect(pos, size)` | Random point inside rectangle each spawn |
| `circ(center, radius)` | Random point inside circle each spawn (area-uniform) |
| `sampler(v2, v2)` | Random point in axis-aligned box |

`pos:` shape objects are mutable and shared — mutate the rect/circ at runtime to move where future particles spawn (live particles unaffected).

**Shape DSL** — `shape:` + `size:` meaning:

| Shape | `size:` meaning |
|---|---|
| `:pixel` | ignored |
| `:rect` | `v2(w, h)` — rectangle dimensions, drawn centered, rotates with `ang_vel` |
| `:circle` | radius — uses `size.x` for v2 forms |
| `:line` | `v2(dx, dy)` — direction vector from particle pos, rotates with `ang_vel` |

When `size:` is a `range()` array, it curves over life. Float arrays scale uniformly (circles shrink/grow radius, rects scale both axes, lines scale direction vector). Vector2 arrays interpolate per-component.

**Drag** — `drag:` and `ang_drag:` are multiplicative per-tick reduction in (angular) velocity. `drag: 0.05` loses 5% velocity per tick. Clamped to `[0, 1]`. For acceleration use `accel:` / `ang_accel:`.

**Color over life** — `color:` accepts a `range()` Color array. Concat ranges for stepped/piecewise effects:

```ruby
color: range(P.yellow, P.orange, 3) +
       range(P.orange, P.red, 4) +
       range(P.red, P.dark_gray, 5),
```

**Methods on Particles:**

| Signature | Returns | Notes |
|---|---|---|
| `p.draw` | self | Render alive particles. Place in `draw` or `ui` for draw-order control |
| `p.burst(n)` | self | Emit `n` particles immediately |
| `p.start` | self | Resume continuous emission |
| `p.stop` | self | Pause emission (alive particles keep ticking) |
| `p.running?` | bool | |
| `p.count` | Integer | Currently alive |
| `p.max` | Integer | Ring buffer capacity |
| `p.pos` / `p.pos = x` | v2/rect/circ/sampler | Replace pos spec for future spawns |
| `p.destroy` | nil | Remove from tick list, free storage |

### `sampler`

Deferred uniform random — sampled per particle at spawn time. Unlike `randf_range` (which returns an immediate float), `sampler` is a descriptor that the particle system evaluates natively.

| Signature | Returns | Notes |
|---|---|---|
| `sampler(lo, hi)` | Sampler | `lo`/`hi` both Numeric or both Vector2 |
| `s.lo` | Numeric or Vector2 | |
| `s.hi` | Numeric or Vector2 | |

```ruby
sampler(0.3, 0.8)                          # Float — random lifetime
sampler(v2(-80, -120), v2(80, -20))        # Vector2 — random velocity
```

### Examples

**Rain:**

```ruby
RAIN = particles(
  max: 200, rate: 80, lifetime: 1.5,
  pos: rect(v2(-5, -10), v2(330, 1)),
  velocity: v2(-2, 325),
  shape: :line, size: v2(0, -3),
  color: P.blue,
)

def draw
  clear(P.black)
  RAIN.draw
end
```

**Explosion — color ramp, drag, gravity ramp:**

```ruby
BOOM = particles(
  max: 200, rate: 0,
  lifetime: sampler(0.5, 1.0),
  pos: v2(160, 120),
  velocity: sampler(v2(-80), v2(80)),
  accel: range(v2(0), v2(0, 150), 10),      # gravity ramps up
  drag: 0.04,                                  # 4% velocity loss per tick
  shape: :circle,
  size: range(0, 6, 3) + [6, 6, 6] + range(6, 0, 5),
  color: range(P.yellow, P.orange, 3) +
         range(P.orange, P.red, 3) +
         range(P.red, P.dark_gray, 4) +
         range(P.dark_gray, P.light_gray, 3),
)

def update(dt)
  BOOM.burst(50) if pressed?(:space)
end
```

---

## Spawner

A `Spawner` triggers a block on a recurring cadence. Use it for enemy waves, bullet patterns, periodic pickup drops, or any "particles-like" emission at game-object granularity. Pure Ruby helper built on `every`, so any spawn logic you can express in Ruby goes inside the block — the engine stays out of placement, object construction, and patterns.

Unlike `particles`, which manages lightweight visual effects natively, a spawner is just a timer with a name. The block is where you construct game objects, fire bullets, pick positions, etc.

### `spawner`

```ruby
spawner(rate:, count: 1, start: true) { |this| ... } -> Spawner
```

| Arg | Type | Notes |
|---|---|---|
| `rate:` | Numeric or Range | Seconds between emissions. A Range (e.g. `(1.0..3.0)`) is resampled each schedule for natural variance. |
| `count:` | Integer or Range | Block invocations per tick (burst size). Ranges sampled each tick. Default `1`. |
| `start:` | bool | Begin firing immediately. Default `true`. Pass `false` to configure, then call `.start`. |
| `&block` | required | `|this|` is the parent GameObject via `init(parent)`, or `nil` standalone — same convention as Timer. |

Follows the `init(parent)` convention: when used as a field on `obj(...)`, `this` inside the block is the owning object.

```ruby
BOSS = obj(
  pos: v2(0),
  hp: 100,
  gun: spawner(rate: 1.0) { |this| fire_bullet_ring(this.pos) }
)

# later
BOSS.gun.stop           # pause emission
BOSS.gun.start          # resume
BOSS.gun.rate = 0.5     # twice as fast; reschedules on next tick
BOSS.gun.fire!          # force one immediate emission cycle
```

Range rate + burst:

```ruby
swarm = spawner(rate: (0.3..0.8), count: (3..6)) do |this|
  spawn_enemy(at: random_point_in(SPAWN_AREA))
end
```

Standalone (no parent) — `this` is `nil`:

```ruby
spawner(rate: 5.0) { spawn_wave }
```

| Method | Returns | Notes |
|---|---|---|
| `s.start` | self | Begin firing; no-op if already running |
| `s.stop` | self | Cancel internal timer; emission halts |
| `s.running?` | bool | |
| `s.fire!` | self | Force one immediate emission cycle (`count` block calls) outside normal cadence |
| `s.rate` / `s.rate=` | Numeric or Range | Mutable at runtime; reschedules on next tick |
| `s.count` / `s.count=` | Integer or Range | |
| `s.parent` | GameObject or nil | Set by `init(parent)` when used as an `obj(...)` field |

**Lifecycle note.** If a spawner is a field on a GameObject that later goes away, the internal timer keeps firing. Call `.stop` explicitly when you're done with it (e.g. from the parent's death FSM transition).

---

## Timers

Fire a block once after a delay (`after`) or repeatedly on an interval (`every`). Both return a `Timer` handle. Timers tick once per fixed-timestep update.

| Signature | Returns | Notes |
|---|---|---|
| `after(seconds) { \|this\| ... }` | Timer | Fires once, then auto-removes |
| `every(seconds, leading: false) { \|this\| ... }` | Timer | Fires repeatedly until cancelled. `leading: true` fires once on the next tick instead of waiting `seconds` first |
| `t.cancel` | nil | Stops the timer; safe to call repeatedly |
| `t.cancelled?` / `t.finished?` | bool | |
| `t.repeating?` | bool | |
| `t.interval` / `t.elapsed` / `t.remaining` | Float | Seconds. `remaining` clamps at 0 |

The block's `this` parameter is whatever object the timer was attached to via `init(parent)`. `obj()` calls `init` automatically on any field that responds to it (same convention as `fsm`):

```ruby
PLAYER = obj(
  hp: 10,
  pos: v2(0),
  burn: every(1.0) { |this| this.hp -= 1 }
)

# stop it later
PLAYER.burn.cancel
```

Standalone (no parent) is fine — the block just gets `nil`:

```ruby
every(10) { spawn_wave }
after(0.5) { play_sound(:explode) }
```

If a timer's block raises, the timer is cancelled (one warning, no recurring crash).

Common FSM pattern — store the timer on `state.data` so `exit:` can cancel it:

```ruby
state(
  :calm,
  enter: ->(this, state) {
    state.data.timer = after(STORM_INTERVAL) { this.fsm.transition(:storm) }
  },
  exit: ->(this, state) {
    state.data.timer.cancel
  }
)
```

---

## Camera

Every `draw` call is camera-transformed. `ui` is not.

| Signature | Returns | Notes |
|---|---|---|
| `camera(target: nil, zoom: 1, offset: nil)` | Camera | Creates and activates a camera |
| `c.active` / `c.active = yn` | bool | Only one active at a time |
| `c.target` / `c.target = v2` | Vector2 | Focal point in world space |
| `c.zoom` / `c.zoom = f` | Float | |
| `c.offset` / `c.offset = v2` | Vector2 | Screen-space offset |
| `c.reset(target: true, zoom: true)` | nil | Restore to initial values |

```ruby
CAM = camera(target: v2(160, 120), zoom: 2.0)

def update(dt)
  CAM.target = CAM.target.lerp(PLAYER.pos, 0.1)
end
```

---

## Screen Shake

A sampled noise-based shake. Apply the `offset` to whatever you want to shake.

| Signature | Returns | Notes |
|---|---|---|
| `shake` | Shake | Creates a new shake instance |
| `s.shake(duration, frequency, amplitude)` | nil | Trigger a shake |
| `s.offset` | Vector2 | Current shake offset (decays automatically) |

```ruby
SHAKE = shake

def update(dt)
  SHAKE.shake(0.3, 20, 4) if pressed?(:space)
end

def draw
  CAM.offset = v2(160, 120) + SHAKE.offset
  # ...
end
```

---

## Game Objects

`obj()` is a dynamic property/method container — a lightweight entity. It's Ruby objects with attrs and lambda methods, plus a few engine-managed fields (`pos`, `rotation`, `scale`, `visible`).

| Signature | Returns | Notes |
|---|---|---|
| `obj(**attrs)` | GameObject | |
| `o.pos` / `o.pos = v2` | Vector2 | Built-in |
| `o.rotation` / `o.rotation = r` | Float | Radians (use `n.to_rad` / `n.to_deg` to convert) |
| `o.scale` / `o.scale = v2` | Vector2 | |
| `o.visible` / `o.visible = yn` | bool | |

Any extra kwargs become attrs with auto-generated getters and setters. Values that are `Proc`/`lambda` become methods on the object, with the object passed as the first argument.

**Lifecycle hook:** pass `init: ->(this) { ... }` to run logic after all kwargs are processed and the physics body (if any) is attached. Fires once per `obj()` call. `this` is fully constructed at this point.

**Automatic attach of subfields:** engine-internal subcomponents (`Spawner`, `Timer`, `FSM`) auto-receive a back-reference to the owning object during `obj()` construction via a private `_attach(parent)` hook. No manual wiring. If you reassign those fields *after* construction, they're not re-attached — call `_attach` yourself.

```ruby
PLAYER = obj(
  pos: v2(100),
  health: 100,
  velocity: v2(0),

  update: ->(this, dt) {
    this.pos += this.velocity * dt
  },

  draw: ->(this) {
    PLAYER_SPRITE.draw(this.pos)
  }
)

def update(dt); PLAYER.update(dt); end
def draw; PLAYER.draw; end
```

---

## State Machines

Used for per-entity state (player idle/run/jump) or game states (menu/play/paused).

| Signature | Returns | Notes |
|---|---|---|
| `state(name, enter: nil, update: nil, exit: nil)` | State | Callbacks receive `(this, state, ...)` depending on arity |
| `fsm(default:, states:)` | FSM | |
| `f.update(dt)` | nil | Drives the current state |
| `f.transition(name)` | nil | Force a transition |
| `f.state` | State | Current state |
| `s.name` | Symbol | |
| `s.data` | GameObject | Per-state scratch — assign anything: `state.data.timer = after(...) { ... }` |
| `s.fsm` | FSM | Parent FSM |
| `s.transition(name)` | nil | Shortcut for `state.fsm.transition(name)` |
| `s == :symbol` | bool | Compares by name |

State callback arities are detected automatically:

- 0-arg: `->() { ... }`
- 1-arg: `->(this) { ... }`
- 2-arg: `->(this, state) { ... }`
- 3-arg (update only): `->(this, state, dt) { ... }`

```ruby
PLAYER = obj(
  pos: v2(100),
  sprite: sprite(PLAYER_TEX, size: v2(16)),

  fsm: fsm(default: :idle, states: [
    state(:idle,
      enter: ->(this) { this.sprite.frame = 0 },
      update: ->(this, state, dt) {
        state.transition(:run) if get_axis(%i{a d}, %i{w s}).length > 0
      }
    ),
    state(:run,
      update: ->(this, state, dt) {
        WALK_ANIM.update(dt)
        this.sprite.frame = WALK_ANIM.frame
      }
    )
  ])
)

def update(dt) = PLAYER.fsm.update(dt)
```

---

## Collision/Physics

Box2D-backed physics. Enable on a game object by passing `body:` to `obj(...)`. The collision shape is derived from the object's `shape:` kwarg — `Circ` → box2d circle, `Rect` → box2d polygon.

**Body kwargs on `obj(...)`:**

| Kwarg | Type | Notes |
|---|---|---|
| `body:` | `:static` / `:kinematic` / `:dynamic` | Omit for no physics (unless `sensor: true`, which defaults to `:static`) |
| `shape:` | `Circ` or `Rect` | **Required** when `body:` is set. Drives collision geometry |
| `sensor:` | bool | Pass-through "trigger" — generates events without blocking movement |
| `layer:` | Integer `1..64` or Array | Layer(s) this body is ON |
| `mask:` | Integer `1..64` or Array | Layer(s) this body interacts WITH. Default for non-sensors: all layers. Default for sensors: none — must opt in |
| `density:` | Float | Default `1.0` (dynamic mass calculation) |
| `friction:` | Float | Default `0.3` (tangential contact resistance) |
| `restitution:` | Float | Default `0.0` (bounciness, 0 = dead stop, 1 = elastic) |
| `drag:` | Float | Default `0.0` (linear damping — velocity bleed per step) |

**Body types:**
- `:static` — never moves (walls, level geometry)
- `:kinematic` — moved manually via `pos=` or `move()` (players, platforms, bullets)
- `:dynamic` — simulated, responds to forces, gravity, contacts

**Body center positioning:** the body's collision center is derived from the shape's natural origin. For `circ(r)` (no offset), `pos` is the center. For `rect(v2(w,h))` (no offset), `pos` is the top-left — matches how each shape draws.

**Lifecycle:**

| Signature | Returns | Notes |
|---|---|---|
| `o.destroy_body` | nil | Tear down the box2d body immediately. Idempotent. Mruby object lives until GC |

User code typically wraps this in its own `destroy`:

```ruby
destroy: ->(this) {
  this.destroy_body
  g.bullets.delete(this)
}
```

**GameObject physics methods:**

| Signature | Returns | Notes |
|---|---|---|
| `o.move(velocity, dt)` | Vector2 | Mover API for kinematic bodies. Cast + slide. Returns velocity clipped by collision planes |
| `o.velocity` / `o.velocity = v2` | Vector2 | Dynamic body linear velocity |
| `o.impulse(v2)` | self | Instant velocity change (dynamic only) |
| `o.force(v2)` | self | Continuous force (dynamic only) |
| `o.overlaps?(other)` | bool | AABB overlap test between two bodies |
| `o.overlapping` | Array[GameObject] | Sensor-only. Objects currently inside this sensor, filtered by `mask` |

**Sensor events:** sensors fire callbacks on begin/end of overlap.

| Kwarg | Signature | Notes |
|---|---|---|
| `on_enter:` | `->(this, other) { }` | Fires when `other` enters this sensor's area |
| `on_exit:` | `->(this, other) { }` | Fires when `other` leaves |

Dispatch rules: every object involved in a sensor interaction gets exactly one `on_enter`/`on_exit` per event — whether it's the sensor or the visitor, whether the other side is sensor or non-sensor.

**World methods:**

| Signature | Returns | Notes |
|---|---|---|
| `gravity(v2)` or `gravity(n)` | nil | Set world gravity. Number form is y-only |
| `raycast(origin, direction, mask)` | `[hit, point, normal, fraction]` | Ray against all bodies on layers in `mask` |

**Layers:** plain integers `1..64`. Pass a single int or an array for multi-layer: `layer: [1, 3]`.

**Filter semantics:** a contact (solid-vs-solid or sensor-vs-anything) happens only when each side's `layer` is in the other side's `mask`.

- **Non-sensors** default `mask` to all layers → walls/scenery work as passive targets without declaring a mask. Override to restrict (e.g. bullets that pass through the player).
- **Sensors** default `mask` to none → explicit opt-in for what they listen to. Bare sensor with only `layer:` fires zero events.

```ruby
WALL = obj(
  pos: v2(0, 200),
  shape: rect(v2(320, 16)),
  body: :static,
  layer: 1         # no mask needed — passive target
)

PLAYER = obj(
  pos: v2(100),
  shape: circ(8),
  body: :kinematic,
  layer: 2,
  mask: [1, 3]     # blocks on walls, triggers coins
)

COIN = obj(
  pos: v2(50),
  shape: circ(4),
  sensor: true,    # body defaults to :static
  layer: 3,
  mask: 2,         # only player triggers it
  on_enter: ->(this, other) {
    g.score += 10
    this.destroy_body
  }
)

def update(dt)
  vel = get_axis(%i{a d}, %i{w s}) * 100
  PLAYER.move(vel, dt)
end
```

**Notes:**
- `move` uses a capsule approximating the body shape. Sliding is automatic.
- Dynamic bodies sync position back to `obj.pos` each physics step — don't fight it with manual `pos=`; apply forces/velocity instead.
- Pre-step sync pushes `obj.pos` and `obj.rotation` to box2d for static/kinematic bodies, so in-place mutations like `this.pos.y -= n` or `this.rotation += dt` work. Bodies are created with `fixedRotation = true` — orientation is script-driven, not physics-driven.
- `move` rounds to the nearest pixel to avoid sub-pixel drift.
- Physics runs at fixed 60Hz regardless of render `fps()` — simulation is deterministic.

---

## Navigation

Navmesh-driven pathfinding. Works with physics obstacles in its mask layers.

| Signature | Returns | Notes |
|---|---|---|
| `navigator(bounds:, mask: nil, holes: nil, margin: 0)` | Navigator | See kwargs below |
| `n.target = v2` | Vector2 | Goal position. Out-of-mesh points snap to the nearest walkable spot |
| `n.target` | Vector2 or nil | |
| `n.next_position` | Vector2 | Where the agent should move toward this frame. Call once per `update` |
| `n.path` | Array[Vector2] | Current corner waypoints (from agent to target) |
| `n.path_count` | Integer | Cheap `len(path)` |
| `n.arrived?` | bool | True when within ~0.5px of the goal |
| `n.recalculate` | self | Rebuild navmesh (call when static `holes:` change, or after adding/removing Box2D bodies) |
| `n.snap` / `n.snap = f` | Float | Quantize `next_position` to this grid. `0` = off |
| `n.draw_debug` | self | Translucent navmesh + path + target overlay. Call from `draw` or `ui` |

**Constructor kwargs:**

- `bounds:` — the walkable region. Accepts `Array[Vector2]`, `Rect`, `Circ`, or `Poly`. Required
- `mask:` — Box2D layer number (1..64) or Array of layer numbers. Bodies on these layers are extracted as navmesh holes every `recalculate`
- `holes:` — static obstacles. Array of shapes (same types as `bounds:`). Use for level geometry that doesn't have a physics body
- `margin:` — agent radius in px. Shrinks `bounds:` inward and inflates every hole outward so the agent's center path keeps that clearance from walls

`n.draw_debug` renders the navmesh, path, and current target. Place it in `draw` or `ui` for whichever draw-order you want.

```ruby
LEVEL = rect(v2(0), resolution)
WALL = rect(v2(60), v2(20))

PLAYER = obj(
  pos: v2(20),
  speed: 60,
  navigator: navigator(
    bounds: LEVEL,
    holes:  [WALL],
    margin: 8 # keep 6px clear of walls
  ),
  update: ->(this, dt) {
    this.navigator.target = mouse if down?(:left_mouse)
    this.pos = this.pos.move_toward(this.navigator.next_position, this.speed * dt)
  },
  draw: ->(this) {
    circ(this.pos, 8).draw(color: P.red, filled: true)
  }
)

def update(dt)
  quit if pressed?(:escape)
  PLAYER.update(dt)
end
def draw
  WALL.draw(filled: true)
  PLAYER.draw
end
```

`next_position` returns the agent's current position (so it stands still) when the target sits in a region disconnected from the agent — rather than marching in a straight line through a wall.

---

## Events

A simple publish/subscribe queue. Dispatched events are delivered to subscribers *and* to the top-level `event(e)` callback.

| Signature | Returns | Notes |
|---|---|---|
| `dispatch(message, data=nil)` | nil | Queue an event |
| `subscribe(message_or_array, callback)` | Proc | Returns an unsubscribe proc |
| `unsubscribe(message_or_array, sub)` | nil | |

**CustomEvent** (what your callback / `event(e)` receives):

| Signature | Returns |
|---|---|
| `e.message` | Symbol |
| `e.data` | any |

Subscriber callbacks can take 0 or 1 arguments; arity is detected.

```ruby
subscribe(:coin_collected, ->(e) { g.score += e.data[:value] })

def update(dt)
  dispatch(:coin_collected, value: 100) if PLAYER.overlaps?(COIN)
end
```

---

## Numeric Helpers

Mini9 adds these methods to `Numeric` (so `Integer` and `Float` both get them).

| Signature | Returns | Notes |
|---|---|---|
| `n.move_toward(target, delta)` | Float | |
| `n.lerp(target, weight)` | Float | |
| `n.clamp(min, max)` | Float | |
| `n.wrapf(min, max)` | Float | Float-aware wrap |
| `n.sign` | Integer | -1, 0, or 1 |
| `n.zero_approx?(epsilon=1e-5)` | bool | |
| `n.equal_approx?(other, epsilon=1e-5)` | bool | |
| `n.grid_pos(width, height=width)` | Vector2 or nil | Index → 2D coordinate (inverse of `Vector2#grid_index`) |
| `n.to_rad` | Float | Degrees → radians |
| `n.to_deg` | Float | Radians → degrees |
| `randf_range(min, max)` | Float | Standalone function, not a Numeric method |

---

## Global Store

`g` is a per-game global bag. Any attribute you assign becomes persistent for the session.

```ruby
g.score = 0
g.level = 1
g.game_state = :menu

# anywhere else
g.score += 100
```

No declaration needed. Getters and setters are created on first assignment.

---

## File Data

Simple file loading for game data (levels, configs, text).

| Signature | Returns | Notes |
|---|---|---|
| `file(path)` | DataFile | Loads the file immediately |
| `f.lines` | Array[String] | Non-empty lines, trimmed |
| `f.path` | String | |

```ruby
LEVEL = file("assets/level1.txt")
LEVEL.lines.each_with_index { |row, y| parse_row(row, y) }
```

---

## Save & Load

Persistent key-value store. One JSON blob per game. On native, written sibling
to the `.rom` (or `save.m9` inside the game dir when running unpackaged). On web,
stored in `localStorage` under a key derived from the source dir basename at
package time — survives `.rom` renames, doesn't collide across games.

Plain JSON on disk — players can hand-edit their save. That's intentional.

| Signature | Returns | Notes |
|---|---|---|
| `save(key, value)` | nil | Stores `value` under `key`. `nil` value removes the key. |
| `load(key)` | value or nil | Returns `nil` if key absent or no save exists yet. |

Top-level keys passed to `save`/`load` are coerced to String — so
`save(:foo, ...)` and `save("foo", ...)` reach the same slot.

```ruby
# top-level: rehydrate on startup
g.score    = load(:high_score) || 0
g.unlocks  = load(:unlocks)    || []

def update
  g.score += 1 if some_condition

  if game_over?
    save(:high_score, g.score)
    save(:unlocks, g.unlocks << current_level_id)
  end
end
```

```ruby
# multiple "slots" — just use different keys
save("slot1", { level: 3, hp: 80 })
save("slot2", { level: 7, hp: 100 })
load("slot1")         # => {"level"=>3, "hp"=>80}
save("slot1", nil)   # delete slot
```

Hash keys inside values may be Symbol or String, freely mixed. `load` returns
hashes wrapped in [`IndifferentHash`](#indifferenthash) so both
`data[:level]` and `data["level"]` look up the same entry. Nested hashes are
wrapped recursively.

Values must be JSON-safe: `Hash` / `Array` / `Integer` / `Float` / `String` /
`true` / `false` / `nil`. Symbol *values* and any other type raise
`ArgumentError` — convert before saving (`save(:name, sym.to_s)`) so the load
side has no ambiguity about what type comes back.

### IndifferentHash

A Hash-like container where Symbol and String keys are equivalent. `data[:hp]`
and `data["hp"]` look up the same entry; same for `key?`, `fetch`, `dig`,
`delete`, `[]=`. Exposed as a general utility — handy whenever game data
crosses the Symbol/String boundary.

```ruby
BOSSES = IndifferentHash.new(grunk: false, grog: false, uglug: false)
# later: current_boss.name returns the String "grunk"
BOSSES[current_boss.name] = true   # finds the :grunk entry, not a new one
```

---

## Debug & System

| Signature | Returns | Notes |
|---|---|---|
| `metrics(yn=nil)` | bool | Show FPS/metrics overlay |
| `log(*args)` | nil | Print to console. Pass `--log-level debug` on CLI for verbose engine tracing |

---

## Importing Code

Split your game across files with `import`. Each import is relative to the game's root directory.

```ruby
# main.rb
import(:player)             # loads player.rb
import(:enemy)              # loads enemy.rb
import("states/idle")       # loads states/idle.rb
import(:states, :idle)      # same as above
```

`import` executes the target file at the top level of `Object`, so constants defined inside become global. Returns the result of the imported file.

---

## Cookbook

Short complete examples showing how the APIs fit together. `P` (the default palette) is predefined — no setup needed.

### Animated player

WASD movement with a walking animation that flips horizontally based on direction.

```ruby
PLAYER_TEX = texture("assets/player.png")
WALK = anim(interval: 0.08, values: [0, 1, 2, 3])

PLAYER = obj(
  pos: v2(160, 120),
  sprite: sprite(PLAYER_TEX, size: v2(16)),
  speed: 80
)

def update(dt)
  dir = get_axis(%i{a d}, %i{w s})
  PLAYER.pos += dir * PLAYER.speed * dt

  if dir.length > 0
    WALK.update(dt)
    PLAYER.sprite.frame = WALK.current
    PLAYER.sprite.fliph = true  if dir.x < 0
    PLAYER.sprite.fliph = false if dir.x > 0
  else
    PLAYER.sprite.frame = 0
  end
end

def draw
  clear(P.black)
  PLAYER.sprite.draw(PLAYER.pos)
end
```

### Score with events and global store

Decoupled scoring: anything in the game can `dispatch(:coin_collected, ...)`, and the score updates without the dispatcher knowing about it.

```ruby
g.score = 0

subscribe(:coin_collected, ->(e) { g.score += e.data[:value] })

def update(dt)
  dispatch(:coin_collected, value: 10) if pressed?(:space)
end

def ui
  text("SCORE #{g.score}", Font::SMALL).draw(offset: v2(4), color: P.white)
end
```
