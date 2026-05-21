<img src="./assets/mini9.png" alt="mini9" width=674 />

A 2D game framework for writing games with Ruby. More batteries than a fantasy console, less than an engine.

See [DOCS.md](DOCS.md) for the full API reference.

### Quick Start

Make a directory with a `main.rb`:

```ruby
g.target = resolution/2

def update
  quit if pressed?(:escape)
  g.target = g.target.move_toward(mouse, 50*dt)
end

def draw
  rect(v2(16)).draw(offset: g.target - v2(8), filled: true, color: P.blue)
  circ(5).draw(offset: mouse, filled: true, color: P.yellow)
end
```


## Usage

Download latest release, put it in `PATH`. <small>I have no idea if any of this works on Windows and I provide no consideration whatsoever for that case, so sorry.</small>

### Run your game

```bash
mini9 path/to/mygame
```

### Package a 'cart'

```bash
mini9 package --source path/to/mygame --output .
mini9 mygame.m9
```

### Package for web

```bash
# builds ./mygame dir containing index.html, cart, etc
mini9 package --web --source path/to/mygame --output .

# zip for itch.io or similar
zip -r mygame.zip mygame
```


## Dev

### Prerequisites

- `odin` [2026-05](https://github.com/odin-lang/Odin/releases/tag/dev-2026-05)
- `ruby` 3.4+
- `git`, `cmake`, `make`, `cc`, `bison`, `python3`
- on Linux: `libgl1-mesa-dev libx11-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev libxkbcommon-dev`, `libwayland-dev wayland-protocols`

### Setup dependencies

```bash
bin/build setup
```

### Build (`debug` or `release`)

```bash
bin/build debug
```

### Try it in browser

```bash
bin/build debug --web path/to/mygame
```
