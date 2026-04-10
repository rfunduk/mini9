package main

// mini9 linter
//
// project-specific lint rules built on top of core:odin/parser + core:odin/ast.
// the design is intentionally narrow: each rule is just an entry in RULES with
// a check proc that walks an ast.File and emits Diagnostics. no plugin system,
// no rule DSL - if you want a new rule, add another `Rule` entry below and
// write a check proc.
//
// rules typically use the generic `Visitor` abstraction (see "AST walker"
// below) which calls on_enter/on_exit for every node in depth-first order.
// the rule keeps its own state in `user_data` and switches on `node.derived`
// to handle the cases it cares about.
//
// usage: lint <directory>
//        recursively lints all .odin files in <directory>
//        exits non-zero if any diagnostics are emitted
//
// rules:
//   no-defer-before-raise
//     ruby_raise() longjmps via mrb.raise and never returns to the call
//     site - any defer that is active in an enclosing scope at the moment
//     of the call will be skipped, leaking whatever it was supposed to free.
//     this rule flags any ruby_raise call that has an active defer
//     lexically before it in the same proc body.

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// types
// ============================================================================

Diagnostic :: struct {
	rule:    string,
	pos:     tokenizer.Pos,
	message: string,
}

Rule :: struct {
	name:        string,
	description: string,
	check:       proc(file: ^ast.File, diags: ^[dynamic]Diagnostic),
}

RULES := []Rule {
	{
		name = "no-defer-before-raise",
		description = "ruby_raise must not be called when a defer is active in any enclosing scope",
		check = check_no_defer_before_raise,
	},
}

// ============================================================================
// AST walker
// ============================================================================
//
// generic depth-first walker built on top of core:odin/ast.walk. rules
// supply enter/exit callbacks and their own state via `user_data`. the
// walker handles every AST node type automatically; rules switch on
// `node.derived` to react to whatever they care about.
//
// the on_exit callback receives the node that's being left, which is what
// makes scope-tracking rules clean: push state in on_enter when you see a
// Block_Stmt, pop in on_exit when you see the same.

Visitor :: struct {
	on_enter:  proc(v: ^Visitor, node: ^ast.Node),
	on_exit:   proc(v: ^Visitor, node: ^ast.Node),
	user_data: rawptr,

	// internal: bridges core:odin/ast.walk's nil-on-exit signaling to
	// our typed on_exit callback. depth-first traversal makes this a
	// simple LIFO stack.
	stack:     [dynamic]^ast.Node,
}

walk_file :: proc(v: ^Visitor, file: ^ast.File) {
	defer delete(v.stack)
	inner := ast.Visitor {
		visit = visit_bridge,
		data  = v,
	}
	for decl in file.decls {
		ast.walk(&inner, decl)
	}
}

visit_bridge :: proc(inner: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
	v := cast(^Visitor)inner.data
	if node != nil {
		append(&v.stack, node)
		if v.on_enter != nil { v.on_enter(v, node) }
	} else if len(v.stack) > 0 {
		top := v.stack[len(v.stack) - 1]
		pop(&v.stack)
		if v.on_exit != nil { v.on_exit(v, top) }
	}
	return inner
}

// ============================================================================
// rule: no-defer-before-raise
// ============================================================================

Defer_Scope :: struct {
	defers: [dynamic]tokenizer.Pos,
}

// state for the defer rule. `chains` is a stack of defer-scope chains -
// one chain per enclosing proc, since defers do not leak across proc
// boundaries. within a chain, scopes are pushed/popped per Block_Stmt.
Defer_Rule_State :: struct {
	diags:  ^[dynamic]Diagnostic,
	chains: [dynamic][dynamic]Defer_Scope,
}

check_no_defer_before_raise :: proc(file: ^ast.File, diags: ^[dynamic]Diagnostic) {
	state := Defer_Rule_State {
		diags = diags,
	}
	defer destroy_defer_rule_state(&state)

	v := Visitor {
		on_enter  = defer_rule_on_enter,
		on_exit   = defer_rule_on_exit,
		user_data = &state,
	}
	walk_file(&v, file)
}

destroy_defer_rule_state :: proc(s: ^Defer_Rule_State) {
	for ci in 0 ..< len(s.chains) {
		for si in 0 ..< len(s.chains[ci]) {
			delete(s.chains[ci][si].defers)
		}
		delete(s.chains[ci])
	}
	delete(s.chains)
}

defer_push_chain :: proc(s: ^Defer_Rule_State) {
	append(&s.chains, make([dynamic]Defer_Scope))
}

defer_pop_chain :: proc(s: ^Defer_Rule_State) {
	if len(s.chains) == 0 { return }
	last := len(s.chains) - 1
	for si in 0 ..< len(s.chains[last]) {
		delete(s.chains[last][si].defers)
	}
	delete(s.chains[last])
	pop(&s.chains)
}

defer_push_scope :: proc(s: ^Defer_Rule_State) {
	if len(s.chains) == 0 { return }
	ci := len(s.chains) - 1
	append(&s.chains[ci], Defer_Scope{defers = make([dynamic]tokenizer.Pos)})
}

defer_pop_scope :: proc(s: ^Defer_Rule_State) {
	if len(s.chains) == 0 { return }
	ci := len(s.chains) - 1
	if len(s.chains[ci]) == 0 { return }
	si := len(s.chains[ci]) - 1
	delete(s.chains[ci][si].defers)
	pop(&s.chains[ci])
}

defer_record :: proc(s: ^Defer_Rule_State, pos: tokenizer.Pos) {
	if len(s.chains) == 0 { return }
	ci := len(s.chains) - 1
	if len(s.chains[ci]) == 0 { return }
	si := len(s.chains[ci]) - 1
	append(&s.chains[ci][si].defers, pos)
}

defer_rule_on_enter :: proc(v: ^Visitor, node: ^ast.Node) {
	s := cast(^Defer_Rule_State)v.user_data

	#partial switch n in node.derived {
	case ^ast.Proc_Lit:
		defer_push_chain(s)

	case ^ast.Block_Stmt:
		defer_push_scope(s)

	case ^ast.Defer_Stmt:
		defer_record(s, n.pos)

	case ^ast.Call_Expr:
		if ident, ok := n.expr.derived.(^ast.Ident); ok {
			if ident.name == "ruby_raise" {
				report_active_defers(s, n.pos)
			}
		}
	}
}

defer_rule_on_exit :: proc(v: ^Visitor, node: ^ast.Node) {
	s := cast(^Defer_Rule_State)v.user_data

	#partial switch _ in node.derived {
	case ^ast.Proc_Lit:
		defer_pop_chain(s)
	case ^ast.Block_Stmt:
		defer_pop_scope(s)
	}
}

report_active_defers :: proc(s: ^Defer_Rule_State, raise_pos: tokenizer.Pos) {
	if len(s.chains) == 0 { return }
	chain := s.chains[len(s.chains) - 1]
	for si in 0 ..< len(chain) {
		for defer_pos in chain[si].defers {
			append(
				s.diags,
				Diagnostic {
					rule = "no-defer-before-raise",
					pos = raise_pos,
					message = fmt.aprintf(
						"ruby_raise called with active defer (declared at %s:%d:%d) - defer would be skipped by longjmp",
						filepath.base(defer_pos.file),
						defer_pos.line,
						defer_pos.column,
					),
				},
			)
		}
	}
}

// ============================================================================
// driver
// ============================================================================

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintfln("usage: %s <directory>", os.args[0])
		os.exit(2)
	}

	root := os.args[1]

	files: [dynamic]string
	defer {
		for f in files { delete(f) }
		delete(files)
	}
	collect_odin_files(root, &files)

	if len(files) == 0 {
		fmt.eprintfln("lint: no .odin files found under %s", root)
		os.exit(2)
	}

	diagnostics: [dynamic]Diagnostic
	defer {
		for d in diagnostics { delete(d.message) }
		delete(diagnostics)
	}

	for path in files {
		lint_file(path, &diagnostics)
	}

	for d in diagnostics {
		fmt.eprintfln("%s:%d:%d: [%s] %s", d.pos.file, d.pos.line, d.pos.column, d.rule, d.message)
	}

	if len(diagnostics) > 0 {
		fmt.eprintfln("\nlint: %d issue(s) found", len(diagnostics))
		os.exit(1)
	}
}

collect_odin_files :: proc(dir: string, out: ^[dynamic]string) {
	fd, open_err := os.open(dir)
	if open_err != nil {
		fmt.eprintfln("lint: cannot open %s: %v", dir, open_err)
		return
	}
	defer os.close(fd)

	entries, read_err := os.read_dir(fd, -1, context.temp_allocator)
	if read_err != nil {
		fmt.eprintfln("lint: cannot read %s: %v", dir, read_err)
		return
	}

	for entry in entries {
		if entry.type == .Directory {
			collect_odin_files(entry.fullpath, out)
		} else if filepath.ext(entry.name) == ".odin" {
			append(out, strings.clone(entry.fullpath))
		}
	}
}

lint_file :: proc(path: string, diags: ^[dynamic]Diagnostic) {
	src, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("lint: could not read %s: %v", path, read_err)
		return
	}
	defer delete(src)

	pkg := ast.Package {
		kind = .Normal,
	}
	file := ast.File {
		pkg      = &pkg,
		src      = string(src),
		fullpath = path,
	}

	p := parser.default_parser()
	if !parser.parse_file(&p, &file) || file.syntax_error_count > 0 {
		// silently skip - the odin compiler will report syntax errors
		return
	}

	for rule in RULES {
		rule.check(&file, diags)
	}
}
