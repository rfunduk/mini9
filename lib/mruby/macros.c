/**
 * macros.c - Thin C wrapper for mruby macros
 */

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/compile.h>
#include <mruby/data.h>
#include <mruby/dump.h>
#include <mruby/gc.h>
#include <mruby/irep.h>
#include <mruby/error.h>
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

/* Frozen check - raises FrozenError if the object is frozen. No-op for
 * immediates (they're conceptually immutable but not flagged). */
void mrbm_check_frozen(mrb_state* mrb, mrb_value v) {
    if (mrb_immediate_p(v)) return;
    mrb_check_frozen(mrb, mrb_basic_ptr(v));
}

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

/* Get arity of a method by symbol - returns -2 if undefined, -1 for C funcs */
mrb_int mrbm_method_arity(mrb_state* mrb, mrb_value obj, mrb_sym mid) {
    struct RClass* c = mrb_class(mrb, obj);
    mrb_method_t m = mrb_method_search_vm(mrb, &c, mid);
    if (MRB_METHOD_UNDEF_P(m)) return -2;
    if (!MRB_METHOD_PROC_P(m)) return -1;
    return mrb_proc_arity(MRB_METHOD_PROC(m));
}

/* Read an exception's message string directly from RException->mesg.
 * mruby stores exception messages on the struct, NOT in the iv table —
 * so iv_get(exc, "mesg") doesn't work. This wraps the internal accessor.
 * Returns nil if the value isn't an exception or has no message. */
mrb_value mrbm_exc_mesg(mrb_state* mrb, mrb_value exc) {
    if (mrb_nil_p(exc)) return mrb_nil_value();
    return mrb_exc_mesg_get(mrb, mrb_exc_ptr(exc));
}

/* Load a precompiled irep at top level, replicating what mrb_load_exec does
 * for source-loaded files. The stock mrb_load_irep_cxt skips the target_class
 * wiring that top-level constant assignment (P = ..., FOO = ...) requires,
 * which is why straight bytecode loading doesn't work for user main.rb even
 * though it works fine for engine API files (those only define classes and
 * methods, no top-level constants on Object).
 *
 * Returns the result of execution, or undef on irep load error (with
 * mrb->exc set to a SCRIPT_ERROR). */
mrb_value mrbm_load_irep_top(mrb_state* mrb, const void* buf, size_t bufsize) {
    mrb_irep* irep = mrb_read_irep_buf(mrb, buf, bufsize);
    if (!irep) {
        /* mirror what mruby's own load.c does — direct assign, no public setter */
        mrb->exc = mrb_obj_ptr(mrb_exc_new_lit(mrb, E_SCRIPT_ERROR, "irep load error"));
        return mrb_undef_value();
    }

    struct RProc* proc = mrb_proc_new(mrb, irep);
    if (!proc) {
        return mrb_undef_value();
    }
    proc->c = NULL;

    /* the three things mrb_load_irep_cxt forgets: target_class on the proc,
     * target_class on the current callinfo, and a top_run that respects them. */
    struct RClass* target = mrb->object_class;
    MRB_PROC_SET_TARGET_CLASS(proc, target);
    if (mrb->c->ci) {
        mrb_vm_ci_target_class_set(mrb->c->ci, target);
    }

    return mrb_top_run(mrb, proc, mrb_top_self(mrb), 0);
}
