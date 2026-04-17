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
  circle(v2(160, 120), 20, color: P.red, filled: true)
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
- [Rectangles](#rectangles)
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
- [Collision](#collision)
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
  text("Score: #{g.score}", v2(4, 4), Font::SMALL)
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

All drawing happens inside `draw` (world-space, camera-transformed) or `ui` (screen-space). Positions are always `Vector2`. Styling is always kwargs. Default color is white.

| Signature | Returns | Notes |
|---|---|---|
| `clear(color)` | nil | Fills the screen. Safe to call in `draw` or once in setup |
| `pixel(pos, color: P.white)` | nil | Single pixel |
| `line(from, to, color: P.white, thickness: 1, clip: nil)` | nil | |
| `rectangle(rect, **opts)` | nil | `rect` form |
| `rectangle(pos, size, **opts)` | nil | `pos, size` form |
| `circle(pos, radius, color: P.white, filled: false, clip: nil)` | nil | `radius` is scalar |
| `oval(pos, size, color: P.white, filled: false, clip: nil)` | nil | `size` is v2 (half-axes) |

Rectangle options (both forms): `color:`, `filled:`, `thickness:`, `rounded:`, `clip:`. `rounded:` is a percentage 0–100.

`clip:` takes a `Rect` (in local coordinates relative to the drawn shape's `pos`) and scissors the draw to that region.

```ruby
rectangle(v2(10, 10), v2(40, 20), color: P.red, filled: true, rounded: 30)
line(v2(0, 0), v2(100, 100), color: P.white, thickness: 2)
circle(v2(50, 50), 8, filled: true)
```

---

## Text & Fonts

| Signature | Returns | Notes |
|---|---|---|
| `text(str, pos, font, **opts)` | nil | All three are required. Pass `nil` for the default font |
| `text_size(str, font, scale: 1, spacing: 1)` | Vector2 | Rendered size without drawing |
| `font(path, size=nil)` | Font | `size` required for TTF/OTF; not needed for `.png` bitmap fonts |

`text` options: `align:` (`Text::LEFT`, `Text::CENTER`, `Text::RIGHT`), `rotation:`, `scale:`, `spacing:`, `color:`, `outline:`.

**Built-in fonts** (always available):

| Constant | Size |
|---|---|
| `Font::TINY` | 5px |
| `Font::SMALL` | 8px |
| `Font::MEDIUM` | 11px |
| `Font::LARGE` | 15px |

**Font instance methods:**

| Signature | Returns |
|---|---|
| `font.name` | String |
| `font.size` | Integer |

```ruby
text("Hello", v2(10, 10), Font::SMALL, color: P.yellow)
MY_FONT = font("assets/pixel.ttf", 16)
text("Custom", v2(10, 30), MY_FONT, align: Text::CENTER)
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
circle(v2(50, 50), 10, color: P.red, filled: true)

# swap to a custom palette — every later P.foo lookup uses the new colors
P.replace(palette("assets/pico8.gpl"))
clear(P.dark_blue)

# or load a separate palette under its own name
PICO = palette("assets/pico8.gpl")
rectangle(v2(0,0), v2(100, 100), color: PICO.dark_blue, filled: true)
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
| `Vector2::ZERO` | `v2(0, 0)` |
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

## Rectangles

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
spr = sprite(tex, size: v2(16, 16))   # 16x16 frames, auto-calculated frame count
spr.frame = 3
spr.fliph = true
spr.draw(v2(100, 100))
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
tween(v2(0, 0), v2(100, 50), 1.0, easing: Easing::CUBIC_OUT) do |pos|
  PLAYER.pos = pos
end
```

`Easing.at(t, easing = Easing::LINEAR)` returns the eased value of `t` (0.0–1.0). Useful standalone.

`range(from, to, count, easing: Easing::LINEAR)` returns an Array of `count` values from `from` to `to`, with easing applied. First and last entries are exactly `from` / `to`. `count` must be ≥ 2. Supports Numeric, Vector2, and Color — type is detected from `from`/`to` (both must match). Feed into `anim`'s `values:` for eased sequences, or pass directly to `particles` for curve-over-life:

```ruby
range(1.0, 0.0, 20)                    # Array of 20 Floats
range(v2(0, 0), v2(100, 50), 10)       # Array of 10 Vector2s
range(P.yellow, P.red, 8)              # Array of 8 Colors (channel-lerped)
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
  velocity: v2(0,0),   # v2 | sampler(v2, v2)
  accel: v2(0,0),      # v2 | sampler(v2, v2) | range(v2)
  drag: nil,           # Float (0..1) | range(Float) — drag amount per tick
  rotation: 0,         # Float radians | sampler(f, f)
  ang_vel: 0,          # Float radians/sec | sampler(f, f)
  ang_accel: 0,        # Float radians/sec² | sampler(f, f) | range(Float)
  ang_drag: nil,       # Float (0..1) | range(Float) — angular drag per tick
  shape: :pixel,       # :pixel | :rect | :circle | :line
  size: v2(1,1),       # v2 | range(Float) | range(v2)
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
  velocity: sampler(v2(-80, -80), v2(80, 80)),
  accel: range(v2(0, 0), v2(0, 150), 10),      # gravity ramps up
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
  pos: v2(0, 0),
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
  pos: v2(0, 0),
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
| `o.init` | nil | Override to run logic when the object is constructed |

Any extra kwargs become attrs with auto-generated getters and setters. Values that are `Proc`/`lambda` become methods on the object, with the object passed as the first argument.

**Automatic init of subfields:** when you pass a value that responds to `init` (e.g. a `Body` or an `FSM`) as a kwarg, `obj()` calls its `init(self)` for you during construction. You don't need to wire up parent references manually. Assigning those fields *after* construction skips this — call `init` yourself in that case.

```ruby
PLAYER = obj(
  pos: v2(100, 100),
  health: 100,
  velocity: v2(0, 0),

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
| `f.init(context)` | self | Sets `this` passed to state callbacks |
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
  pos: v2(100, 100),
  sprite: sprite(PLAYER_TEX, size: v2(16, 16)),

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
# FSM.init(PLAYER) was called automatically by obj()

def update(dt); PLAYER.fsm.update(dt); end
```

---

## Collision

AABB collision with layer/mask bitmasks and swept-AABB resolution.

| Signature | Returns | Notes |
|---|---|---|
| `body(offset: v2(0), size: v2(1), layer: 0, mask: 0)` | Body | |
| `b.init(parent)` | self | Call once with the owning GameObject |
| `b.offset` / `b.offset = v2` | Vector2 | Relative to parent.pos |
| `b.size` / `b.size = v2` | Vector2 | |
| `b.layer` / `b.layer = n` | Integer | Which layer(s) this body is ON |
| `b.mask` / `b.mask = n` | Integer | Which layers this body COLLIDES WITH |
| `b.parent` | GameObject | |
| `b.resolve_collisions(velocity, dt, slide: false)` | `[new_velocity, hits]` | Swept AABB with optional sliding |
| `raycast(origin, direction, target_rect)` | `[hit, point, normal, t]` | Single-shot ray vs rect |

**Layer constants:** `Body::LAYER_1` through `Body::LAYER_15`. Combine with `|` to be on multiple layers.

**CollisionInfo** (returned inside `hits`):

| Signature | Returns |
|---|---|
| `ci.point` | Vector2 |
| `ci.normal` | Vector2 |
| `ci.t` | Float (0–1) |
| `ci.body` | GameObject that owns the body |

```ruby
PLAYER = obj(
  pos: v2(100, 100),
  body: body(size: v2(16, 16), layer: Body::LAYER_1, mask: Body::LAYER_2)
)
# body.init(PLAYER) was called automatically by obj()

def update(dt)
  vel = get_axis(%i{a d}, %i{w s}) * 100
  new_vel, hits = PLAYER.body.resolve_collisions(vel, dt, slide: true)
  PLAYER.pos += new_vel * dt
  hits.each { |hit| puts "hit #{hit.body} at #{hit.point}" }
end
```

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
| `debug(yn=nil)` | bool | Enable debug mode (also via debug build) |
| `metrics(yn=nil)` | bool | Show FPS/metrics overlay |
| `log(*args)` | nil | Print to console (only in debug builds) |

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
  sprite: sprite(PLAYER_TEX, size: v2(16, 16)),
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
  text("SCORE #{g.score}", v2(4, 4), Font::SMALL, color: P.white)
end
```
