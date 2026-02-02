package engine

import "core:c"
import "core:strings"
import mrb "lib:mruby"
import rl "vendor:raylib"

Grid_Data :: union {
	i64,
	f64,
	bool,
}

Grid_Instance :: struct {
	size: rl.Vector2,
	type: typeid,
	data: []Grid_Data,
}

ruby_grid_finalizer :: proc "c" (state: mrb.State, ptr: rawptr) {
	context = global_context

	if ptr != nil {
		obj := cast(^Grid_Instance)ptr
		if obj.data != nil { delete(obj.data) }
		mrb.free(state, ptr)
	}
}

// RUBY FUNCTION: grid(v2(0), type: (:bool,:int,:float)) -> returns Grid
// @engine_method: name="grid", arity=-1
ruby_grid :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context

	size_val: mrb.Value
	kwargs: mrb.Value
	mrb.get_args(state, "o|H", &size_val, &kwargs)

	size_vec := extract_native(rl.Vector2, size_val)
	type: typeid = bool

	if kwargs != mrb.NIL {
		hash := parse_kwargs(state, kwargs)

		if "type" in hash {
			type_str := strings.clone_from_cstring(
				mrb.str_to_cstr(state, mrb.obj_as_string(state, hash["type"])),
				context.temp_allocator,
			)
			switch type_str {
			case "bool":
				type = bool
			case "int":
				type = i64
			case "float":
				type = f64
			}
		}
	}

	size_total := u32(size_vec.x * size_vec.y)
	grid := Grid_Instance {
		size = size_vec^,
		type = type,
		data = make([]Grid_Data, size_total),
	}

	// init default values based on type
	default_val: Grid_Data
	switch type {
	case bool:
		default_val = false
	case i64:
		default_val = i64(0)
	case f64:
		default_val = f64(0.0)
	}
	for i in 0 ..< size_total {
		grid.data[i] = default_val
	}

	grid_ptr := ruby_allocate(Grid_Instance, grid)

	grid_class := mrb.class_get(g.mrb_state, "Grid")
	ruby_obj := mrb.obj_new(g.mrb_state, grid_class, 0, nil)
	mrb.data_init(ruby_obj, grid_ptr, NATIVE_TO_MRUBY_TYPE[Grid_Instance])

	return ruby_obj
}

// RUBY METHOD: g.dimensions -> gets grid dimensions as Vector2
ruby_grid_dimensions :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }
	return create_vector2(obj.size)
}

// RUBY METHOD: g.length -> gets total element count
ruby_grid_length :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }
	return mrb.boxing_int_value(state, c.int(len(obj.data)))
}

// RUBY METHOD: g.type -> gets grid type
ruby_grid_type :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }
	switch obj.type {
	case bool:
		return mrb.symbol_value(mrb.intern_cstr(state, "bool"))
	case i64:
		return mrb.symbol_value(mrb.intern_cstr(state, "int"))
	case f64:
		return mrb.symbol_value(mrb.intern_cstr(state, "float"))
	case:
		panic("The Grid has an invalid type")
	}
}

// RUBY METHOD: g[i] -> get element at index
ruby_grid_get :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }

	index: i32
	mrb.get_args(state, "i", &index)

	if index < 0 || index >= i32(len(obj.data)) {
		return mrb.NIL
	}

	switch obj.type {
	case bool:
		return obj.data[index].(bool) ? mrb.TRUE : mrb.FALSE
	case i64:
		return mrb.boxing_int_value(state, c.int(obj.data[index].(i64)))
	case f64:
		return mrb.word_boxing_float_value(state, obj.data[index].(f64))
	}
	return mrb.NIL
}

// RUBY METHOD: g[i] = val -> set element at index
ruby_grid_set :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }

	index: i32
	value: mrb.Value
	mrb.get_args(state, "io", &index, &value)

	if index < 0 || index >= i32(len(obj.data)) {
		return value
	}

	switch obj.type {
	case bool:
		obj.data[index] = mrb.boolean(value)
	case i64:
		obj.data[index] = i64(mrb.integer(value))
	case f64:
		obj.data[index] = to_f64(value)
	}

	return value
}

// RUBY METHOD: g.each {|el| ...} -> iterate over elements
ruby_grid_each :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }

	block: mrb.Value
	mrb.get_args(state, "&", &block)

	if !mrb.proc_p(block) {
		return self
	}

	for i in 0 ..< len(obj.data) {
		elem: mrb.Value
		switch obj.type {
		case bool:
			elem = obj.data[i].(bool) ? mrb.TRUE : mrb.FALSE
		case i64:
			elem = mrb.boxing_int_value(state, c.int(obj.data[i].(i64)))
		case f64:
			elem = mrb.word_boxing_float_value(state, obj.data[i].(f64))
		}
		mrb.yield(state, block, elem)
	}

	return self
}

// RUBY METHOD: g.update([[i1, v1], [i2, v2], ...]) -> applies specified updates
ruby_grid_update :: proc "c" (state: mrb.State, self: mrb.Value) -> mrb.Value {
	context = global_context
	obj := extract_native(Grid_Instance, self)
	if obj == nil { return mrb.NIL }

	update_value: mrb.Value
	mrb.get_args(state, "A", &update_value)

	// Get array length - handles both embedded and heap arrays
	length := mrb.ary_len(update_value)

	for i in 0 ..< length {
		item := mrb.ary_entry(update_value, c.int(i))
		idx_val := mrb.ary_entry(item, 0)
		val := mrb.ary_entry(item, 1)

		idx := i32(mrb.integer(idx_val))
		if idx >= 0 && idx < i32(len(obj.data)) {
			switch obj.type {
			case bool:
				obj.data[idx] = mrb.boolean(val)
			case i64:
				obj.data[idx] = i64(mrb.integer(val))
			case f64:
				obj.data[idx] = to_f64(val)
			}
		}
	}

	return mrb.NIL
}

setup_grid :: proc() {
	c := create_data_class("Grid")

	mrb.define_method(g.mrb_state, c, "dimensions", cast(rawptr)ruby_grid_dimensions, 0)
	mrb.define_method(g.mrb_state, c, "length", cast(rawptr)ruby_grid_length, 0)
	mrb.define_method(g.mrb_state, c, "type", cast(rawptr)ruby_grid_type, 0)
	mrb.define_method(g.mrb_state, c, "[]", cast(rawptr)ruby_grid_get, 1)
	mrb.define_method(g.mrb_state, c, "[]=", cast(rawptr)ruby_grid_set, 2)
	mrb.define_method(g.mrb_state, c, "each", cast(rawptr)ruby_grid_each, 0)
	mrb.define_method(g.mrb_state, c, "update", cast(rawptr)ruby_grid_update, 1)
}
