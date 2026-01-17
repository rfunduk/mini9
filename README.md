# MINI9

Here we have a game... ... I want to say 'framework'...? Size-wise it's bigger than [pico](https://www.lexaloffle.com/pico-8.php), but not much. And limitations-wise, there certainly are some, but more than [8](https://www.lexaloffle.com/pico-8.php)... see what I'm getting at?

## But really what is it?

I really like pico8 but I'm old and I just want to do whatever I want, right? I like limitations but it's just too much. I want to make art in aseprite and just load it up. I absolutely cannot make a decent sound effect or music to save my life in pico8. Also lua is not really my speed; it's fine, just, I would rather not.

So here we have a _slightly larger_ game framework thing. It's written in [Odin](https://odin-lang.org) and uses [Ruby](https://www.ruby-lang.org/) as the game language (actually [mruby](https://mruby.org/) so no gems/etc).

**Note to self**: Really need a couple examples.

For now you could just make a directory with a `main.rb` in it:

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

...I realise there should probably be API docs because otherwise it'll be near impossible to go further than this. It's similar to pico8 but not _that_ similar.


## More specific details on how to get going.

### Install dependencies

- `python3` in `PATH` is required.
- `odin` in `PATH` is required.
- [`mruby`](https://mruby.org/) is needed, via: `bin/setup`
- Emscripten is how the web magic works, also via: `bin/setup`

Hopefully goes without saying I have no idea if any of this works on Windows and I provide no consideration whatsoever for that case, so sorry.


### Build (`debug` or `release`)

```bash
bin/build.py debug
```

### Run your game

```bash
build/debug/mini9 path/to/game/dir
```

### Try it in browser

```bash
bin/dev_web path/to/game/dir
```

### Package a 'cart'

```bash
build/debug/mini9 package \
  --source path/to/game \
  --output .
build/debug/mini9 game.rom
```

### Package for web

```bash
build/debug/mini9 package --web \
  --source path/to/game \
  --output .
bash -c "cd game && python3 -m http.server"
# visit http://localhost:8080
```

## Misc

### Slopwatch

Did I use an LLM occasionally to help me make sense of the mruby source code, finding obscure references, forum posts, and code snippets etc, to get the bindings working? Yes. Did I vibecode this whole thing resulting in a pile of utter garbage? No. Say no to slop.

### Helpful memory watch:

```bash
watch -n 0.1 'ps -o pid,vsz,rss,comm -p $(pgrep mini9) 2>/dev/null || echo  "Process not running"'
```
