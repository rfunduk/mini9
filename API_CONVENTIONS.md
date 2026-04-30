# Mini9 API Conventions

Internal reference for Ruby API design decisions. Consult before adding or modifying public APIs.

## Argument shape

**Required args are positional. Optional args are kwargs.**

- A default value that makes no sense ⇒ the arg is required.
- `circ(center, radius)` — pos and radius are required, no sensible defaults.
- `r.draw(color: P.white, filled: false, thickness: 1, ...)` — no required args (shape carries its own geometry), styling as kwargs.
- Kwargs are not used to mirror another function's signature. Each function's signature reflects its own requirements.

### Exception: ambiguous positional order

When a constructor has multiple required args whose order would be arbitrary or unintuitive, use named kwargs for all of them, even for required params:

- `anim(interval:, values:, direction: 1, mode: Anim::LOOP)` — `anim(0.1, [1,2,3])` vs `anim([1,2,3], 0.1)` is a coin flip, so name them.
- `fsm(default:, states:)` — same reasoning.

Drawing primitives and similar "obvious order" APIs do NOT qualify for this exception.

### Overloads are fine when they read naturally

`rect(size)`, `rect(pos, size)`, and `rect(x, y, w, h)` are all good Ruby UX. Variable-arity overloads are encouraged when they improve clarity. Single-arg "at origin" defaults (e.g. `circ(r)`, `line(to)`, `oval(size)`) pair with the construct-once-draw-many pattern: build the shape at origin, place it with `.draw(offset: ...)`.

## Naming

- **Predicates end in `?`**: `pressed?`, `down?`, `playing?`, `web?`.
- **No `is_` prefix on predicates**: `zero_approx?`, not `is_zero_approx?`.
- **Loaders follow `noun(path) → Noun`**: `texture`, `sound`, `music`, `font`, `palette`. Even where the returned class name differs from the function name (`file` → `DataFile`), the function itself follows the pattern.
- **Underscore-prefixed methods are internal**: `_key_down_impl`, `_color_int`, `_multiply_scalar`. These are callable but not part of the public API and not documented.

## Shapes render via `.draw(**opts)`

Geometric types (`Rect`, `Circ`, `Line`, `Oval`, `Poly`, `Text`, `Vector2`) carry their own geometry. Rendering is a method on the shape, not a free function. Construct once, draw many times with per-call style kwargs.

- `circ(v2(50), 20).draw(color: P.red, filled: true)` — canonical form.
- No free-function drawing primitives (no `circle(...)`, `rectangle(...)`, etc). `clear(color)` is the one exception — it's not a shape.
- Every shape's `.draw` accepts `offset:` so a shape built at origin can be placed anywhere per-call.

## Setters return the assigned value

Ruby's `obj.foo = x` expression evaluates to `x` regardless of what the setter method body returns. Setter bodies should `return value` to match this semantics — don't return `self`.
