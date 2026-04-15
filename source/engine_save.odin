package engine

import "core:c"
import "core:encoding/json"
import "core:log"
import "core:strings"
import mrb "lib:mruby"

@(private = "file")
save_data: json.Object

@(private = "file")
save_loaded: bool

@(private = "file")
ensure_loaded :: proc() {
	if save_loaded { return }
	save_loaded = true

	data, ok := _save_file_read()
	if !ok || len(data) == 0 { return }
	defer delete(data)

	v, err := json.parse(data, .JSON, true, context.allocator)
	if err != nil {
		log.warnf("[save] parse failed (%v); starting fresh", err)
		return
	}
	obj, is_obj := v.(json.Object)
	if !is_obj {
		log.warnf("[save] root is not an object; starting fresh")
		return
	}
	save_data = obj
}

@(private = "file")
flush :: proc() {
	blob, err := json.marshal(save_data, {pretty = true}, context.temp_allocator)
	if err != nil {
		log.errorf("[save] marshal failed: %v", err)
		return
	}
	if !_save_file_write(blob) {
		log.errorf("[save] write failed")
	}
}

@(private = "file")
mrb_to_json :: proc(state: mrb.State, v: mrb.Value) -> (json.Value, bool) {
	if v == mrb.NIL { return json.Null(nil), true }
	if v == mrb.TRUE { return json.Boolean(true), true }
	if v == mrb.FALSE { return json.Boolean(false), true }
	if mrb.integer_p(v) { return json.Integer(mrb.integer(v)), true }
	if mrb.float_p(v) { return json.Float(mrb.float(v)), true }
	if mrb.string_p(v) {
		cstr := mrb.str_to_cstr(state, v)
		return json.String(strings.clone(string(cstr))), true
	}
	if mrb.array_p(v) {
		n := int(mrb.ary_len(v))
		arr := make(json.Array, 0, n)
		for i in 0 ..< n {
			elem := mrb.ary_entry(v, c.int(i))
			jv, ok := mrb_to_json(state, elem)
			if !ok { return nil, false }
			append(&arr, jv)
		}
		return arr, true
	}
	if mrb.hash_p(v) {
		obj := make(json.Object)
		keys := mrb.hash_keys(state, v)
		n := int(mrb.ary_len(keys))
		for i in 0 ..< n {
			k := mrb.ary_entry(keys, c.int(i))
			// String keys only. The Ruby `save()` wrapper normalizes
			// Symbol → String on the way in, so by the time we get here
			// any non-String key is genuinely unsupported (e.g. Integer, nested Array).
			// Load returns IndifferentHash — sym/string lookups both work.
			if !mrb.string_p(k) { return nil, false }
			kcstr := mrb.str_to_cstr(state, k)
			kstr := strings.clone(string(kcstr))
			val := mrb.hash_get(state, v, k)
			jv, ok := mrb_to_json(state, val)
			if !ok { return nil, false }
			obj[kstr] = jv
		}
		return obj, true
	}
	return nil, false
}

@(private = "file")
json_to_mrb :: proc(state: mrb.State, v: json.Value) -> mrb.Value {
	switch val in v {
	case json.Null:
		return mrb.NIL
	case json.Integer:
		return mrb.fixnum_value(mrb.Int(val))
	case json.Float:
		return mrb.word_boxing_float_value(state, f64(val))
	case json.Boolean:
		return mrb.bool_value(bool(val))
	case json.String:
		cs := strings.clone_to_cstring(string(val), context.temp_allocator)
		return mrb.str_new_cstr(state, cs)
	case json.Array:
		a := mrb.ary_new(state)
		for elem in val {
			mrb.ary_push(state, a, json_to_mrb(state, elem))
		}
		return a
	case json.Object:
		h := mrb.hash_new(state)
		for k, elem in val {
			cs := strings.clone_to_cstring(k, context.temp_allocator)
			key := mrb.str_new_cstr(state, cs)
			mrb.hash_set(state, h, key, json_to_mrb(state, elem))
		}
		return h
	}
	return mrb.NIL
}

// set a key in the save store. nil value removes the key. value must be
// JSON-safe: Hash (string-keyed) / Array / Integer / Float / String / Bool /
// nil. symbol or anything else raises ArgumentError — user converts before
// saving so load-side has no ambiguity. hash string keys only, same reason.
// @engine_method: name="_save_set", arity=2
ruby_save_set :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	key_v, val_v: mrb.Value
	mrb.get_args(state, "oo", &key_v, &val_v)

	key_s := mrb.obj_as_string(state, key_v)
	key_view := string(mrb.str_to_cstr(state, key_s))

	ensure_loaded()
	if save_data == nil { save_data = make(json.Object) }

	if val_v == mrb.NIL {
		// free old key+value if present; key_view is borrowed from mruby, no alloc
		if existing_key, found := find_key_storage(save_data, key_view); found {
			old_val := save_data[key_view]
			delete_key(&save_data, key_view)
			free_json_value(old_val)
			delete(existing_key)
		}
	} else {
		jv, ok := mrb_to_json(state, val_v)
		if !ok {
			return mrb.raise_error(
				state,
				"ArgumentError",
				"save() value contains unsupported type — only Hash / Array / Numeric / String / Bool / nil allowed",
			)
		}
		// replace-in-place: free old value, reuse existing stored key
		if _, found := save_data[key_view]; found {
			free_json_value(save_data[key_view])
			save_data[key_view] = jv
		} else {
			save_data[strings.clone(key_view)] = jv
		}
	}
	flush()
	return mrb.NIL
}

@(private = "file")
find_key_storage :: proc(m: json.Object, k: string) -> (string, bool) {
	// Odin maps return the caller's key view via lookup, not the stored key.
	// need to iterate to get the actual owned string to free.
	for key in m {
		if key == k { return key, true }
	}
	return "", false
}

@(private = "file")
free_json_value :: proc(v: json.Value) {
	#partial switch val in v {
	case json.String:
		delete(string(val))
	case json.Array:
		for elem in val { free_json_value(elem) }
		delete(val)
	case json.Object:
		for k, elem in val {
			delete(k)
			free_json_value(elem)
		}
		m := val
		delete(m)
	}
}

cleanup_save :: proc() {
	if save_data == nil { return }
	for k, v in save_data {
		delete(k)
		free_json_value(v)
	}
	delete(save_data)
	save_data = nil
	save_loaded = false
}

// @engine_method: name="_save_get", arity=1
ruby_save_get :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	key_v: mrb.Value
	mrb.get_args(state, "o", &key_v)

	key_s := mrb.obj_as_string(state, key_v)
	key := string(mrb.str_to_cstr(state, key_s))

	ensure_loaded()
	if save_data == nil { return mrb.NIL }
	v, found := save_data[key]
	if !found { return mrb.NIL }
	return json_to_mrb(state, v)
}
