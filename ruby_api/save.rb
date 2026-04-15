# save / load persistent key-value data. backing store is a small JSON file
# sibling to the .rom (native) or a localStorage entry keyed by game name
# (web). plain text on disk — users can hand-edit their saves. that's a
# feature.
#
# values must be JSON-safe: Hash / Array / Integer / Float / String / true /
# false / nil. anything else (Symbol values, custom objects, etc) raises
# ArgumentError — convert before saving (e.g. `save(:k, sym.to_s)`) so the
# load side has no ambiguity about what type comes back.
#
# Hash keys may be Symbol or String, freely mixed — normalized to String at
# write time. `load` returns hashes wrapped in IndifferentHash, so both
# `data[:hp]` and `data["hp"]` work regardless of how you wrote them.
#
# `save(k, nil)` removes the key.

def save(k, v) = _save_set(k.to_s, _save_normalize(v))
def load(k)    = _save_wrap(_save_get(k.to_s))

def _save_normalize(v)
  case v
  when IndifferentHash then v.to_h.each_with_object({}) { |(hk, hv), h| h[hk.to_s] = _save_normalize(hv) }
  when Hash            then v.each_with_object({})      { |(hk, hv), h| h[hk.to_s] = _save_normalize(hv) }
  when Array           then v.map { |e| _save_normalize(e) }
  else v
  end
end

def _save_wrap(v)
  case v
  when Hash  then IndifferentHash.new(v.each_with_object({}) { |(hk, hv), h| h[hk] = _save_wrap(hv) })
  when Array then v.map { |e| _save_wrap(e) }
  else v
  end
end
