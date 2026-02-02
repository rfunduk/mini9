/**
 * macros.c - Thin C wrapper for mruby macros
 */

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/compile.h>
#include <mruby/data.h>
#include <mruby/gc.h>
#include <mruby/irep.h>
#include <mruby/proc.h>
#include <mruby/value.h>
#include <mruby/internal.h>

/* Type checking - wraps mrb_*_p macros */
enum mrb_vtype mrbm_type(mrb_value v) { return mrb_type(v); }
mrb_bool mrbm_integer_p(mrb_value v) { return mrb_integer_p(v); }
mrb_bool mrbm_fixnum_p(mrb_value v) { return mrb_fixnum_p(v); }
mrb_bool mrbm_float_p(mrb_value v) { return mrb_float_p(v); }
mrb_bool mrbm_symbol_p(mrb_value v) { return mrb_symbol_p(v); }
mrb_bool mrbm_array_p(mrb_value v) { return mrb_array_p(v); }
mrb_bool mrbm_string_p(mrb_value v) { return mrb_string_p(v); }
mrb_bool mrbm_hash_p(mrb_value v) { return mrb_hash_p(v); }
mrb_bool mrbm_cptr_p(mrb_value v) { return mrb_cptr_p(v); }
mrb_bool mrbm_proc_p(mrb_value v) { return mrb_proc_p(v); }
mrb_bool mrbm_data_p(mrb_value v) { return mrb_data_p(v); }
mrb_bool mrbm_nil_p(mrb_value v) { return mrb_nil_p(v); }
mrb_bool mrbm_undef_p(mrb_value v) { return mrb_undef_p(v); }
mrb_bool mrbm_true_p(mrb_value v) { return mrb_true_p(v); }
mrb_bool mrbm_false_p(mrb_value v) { return mrb_false_p(v); }
mrb_bool mrbm_immediate_p(mrb_value v) { return mrb_immediate_p(v); }

/* Value extraction - wraps mrb_* accessor macros */
mrb_int mrbm_integer(mrb_value v) { return mrb_integer(v); }
mrb_int mrbm_fixnum(mrb_value v) { return mrb_fixnum(v); }

#ifndef MRB_NO_FLOAT
mrb_float mrbm_float(mrb_value v) { return mrb_float(v); }
#endif

mrb_sym mrbm_symbol(mrb_value v) { return mrb_symbol(v); }
mrb_bool mrbm_bool(mrb_value v) { return mrb_bool(v); }
void* mrbm_ptr(mrb_value v) { return mrb_ptr(v); }
void* mrbm_cptr(mrb_value v) { return mrb_cptr(v); }

/* Value creation - wraps mrb_*_value inline functions */
mrb_value mrbm_fixnum_value(mrb_int i) { return mrb_fixnum_value(i); }
mrb_value mrbm_symbol_value(mrb_sym s) { return mrb_symbol_value(s); }
mrb_value mrbm_nil_value(void) { return mrb_nil_value(); }
mrb_value mrbm_true_value(void) { return mrb_true_value(); }
mrb_value mrbm_false_value(void) { return mrb_false_value(); }
mrb_value mrbm_bool_value(mrb_bool b) { return mrb_bool_value(b); }
mrb_value mrbm_undef_value(void) { return mrb_undef_value(); }
mrb_value mrbm_obj_value(void* p) { return mrb_obj_value(p); }

/* Array operations - wraps RARRAY_* macros */
mrb_int mrbm_ary_len(mrb_value ary) { return RARRAY_LEN(ary); }
mrb_value* mrbm_ary_ptr(mrb_value ary) { return RARRAY_PTR(ary); }

/* Data object operations - wraps DATA_* macros and mrb_data_init */
void mrbm_data_init(mrb_value v, void* ptr, const mrb_data_type* type) { mrb_data_init(v, ptr, type); }
void* mrbm_data_ptr(mrb_value v) { return DATA_PTR(v); }
const mrb_data_type* mrbm_data_type(mrb_value v) { return DATA_TYPE(v); }

/* Class operations - wraps MRB_SET_INSTANCE_TT macro */
void mrbm_set_instance_tt(struct RClass* c, enum mrb_vtype tt) { MRB_SET_INSTANCE_TT(c, tt); }

/* GC arena operations */
int mrbm_gc_arena_save(mrb_state* mrb) { return mrb_gc_arena_save(mrb); }
void mrbm_gc_arena_restore(mrb_state* mrb, int idx) { mrb_gc_arena_restore(mrb, idx); }

/* GC state access - allows making mrb_state opaque */
size_t mrbm_gc_live(mrb_state* mrb) { return mrb->gc.live; }
size_t mrbm_gc_threshold(mrb_state* mrb) { return mrb->gc.threshold; }
void mrbm_gc_threshold_decrement(mrb_state* mrb, size_t amount) { mrb->gc.threshold -= amount; }

/* CContext operations - allows making mrb_ccontext opaque */
void mrbm_ccontext_set_target_class(mrb_ccontext* c, struct RClass* tc) { c->target_class = tc; }
void mrbm_ccontext_set_keep_lv(mrb_ccontext* c, mrb_bool val) { c->keep_lv = val; }
void mrbm_ccontext_set_no_exec(mrb_ccontext* c, mrb_bool val) { c->no_exec = val; }

/* RProc operations - allows making RProc opaque */
const mrb_irep* mrbm_proc_irep(struct RProc* p) { return p->body.irep; }
void mrbm_proc_set_target_class(mrb_state* mrb, struct RProc* p, struct RClass* tc) { MRB_PROC_SET_TARGET_CLASS(p, tc); }
mrb_int mrbm_proc_arity(mrb_value v) { return mrb_proc_arity(mrb_proc_ptr(v)); }
