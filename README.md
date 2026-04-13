# MINI9

Here we have a game... ... I want to say 'framework'...? Yes, a **game framework**. I'd describe it as bigger than [pico](https://www.lexaloffle.com/pico-8.php)-size, but not much. And limitations-wise, there certainly are some, but it's more flexible than an [8](https://www.lexaloffle.com/pico-8.php)... see what I'm getting at?

## But really what is it?

I really like pico8 but I'm old and I just want to do whatever I want, see? I like limitations but it's just too much. I want to make art in aseprite and just load it up. I absolutely cannot make a decent sound effect or music to save my life in pico8. Also lua is not really my speed; it's fine, but I would rather not.

So here we have a _slightly larger_, _slightly more flexible_ thing. It's written in [Odin](https://odin-lang.org) and uses [Ruby](https://www.ruby-lang.org/) as the game language (actually [mruby](https://mruby.org/) so no gems/etc).

See [DOCS.md](DOCS.md) for the full API reference.

Smallest possible game — directory with a `main.rb`:

```ruby
def update
  quit if pressed?(:escape)
end

def draw
  rectangle(
    mouse-v2(16),
    v2(32),
    filled: true,
    color: Palette::DEFAULT.blue
  )
end
```

See below for how to build & run that.


## More specific details on how to get going.

### Install dependencies

- `odin` in `PATH` is required.
- `ruby` in `PATH` is required.
- [`mruby`](https://mruby.org/) is needed, run: `bin/setup`
- Emscripten is how the web magic works, also via: `bin/setup`

I should put up releases in this repo, but for now you need all that to get this going.

Hopefully goes without saying I have no idea if any of this works on Windows and I provide no consideration whatsoever for that case, so sorry.


### Build (`debug` or `release`)

```bash
bin/build debug
```

### Run your game

```bash
build/debug/mini9 path/to/mygame
```

### Try it in browser

This handy little script relies on `python3` in `PATH` for the webserver.

```bash
bin/dev_web path/to/mygame
```

### Package a 'cart'

```bash
build/debug/mini9 package \
  --source path/to/mygame \
  --output .
build/debug/mini9 mygame.rom
```

### Package for web

```bash
build/debug/mini9 package --web \
  --source path/to/mygame \
  --output .
# ./mygame contains index.html, etc
```

## Misc

### Slopwatch

Did I use an LLM occasionally to help me make sense of the mruby source code, finding obscure references, forum posts, and code snippets etc, to get the bindings working? Yes. Did I vibecode this whole thing resulting in a pile of utter garbage? No. Say no to slop.

### Helpful memory watch:

```bash
watch -n 0.1 'ps -o pid,vsz,rss,comm -p $(pgrep mini9) 2>/dev/null || echo  "Process not running"'
```
