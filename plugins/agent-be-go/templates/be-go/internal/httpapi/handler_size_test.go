// Tests that every handler body stays at 15 code lines or fewer.

package httpapi_test

import (
	"go/ast"
	"go/parser"
	"go/scanner"
	"go/token"
	"io/fs"
	"os"
	"strings"
	"testing"
)

// maxHandlerLines is the most code lines a handler body holds (AGENTS.md, the handler rule): blank
// and comment-only lines do not count, nor do the braces. A longer handler is doing a service's work.
const maxHandlerLines = 15

var here = os.DirFS(".")

func parseHere(t *testing.T, fset *token.FileSet, name string) (*ast.File, []byte) {
	t.Helper()
	src, err := fs.ReadFile(here, name)
	if err != nil {
		t.Fatal(err)
	}
	f, err := parser.ParseFile(fset, name, src, parser.SkipObjectResolution)
	if err != nil {
		t.Fatal(err)
	}
	return f, src
}

// operations reads the method names of StrictServerInterface from the generated server.
func operations(t *testing.T) map[string]bool {
	t.Helper()
	f, _ := parseHere(t, token.NewFileSet(), "api.gen.go")
	ops := map[string]bool{}
	ast.Inspect(f, func(n ast.Node) bool {
		ts, ok := n.(*ast.TypeSpec)
		if !ok || ts.Name.Name != "StrictServerInterface" {
			return true
		}
		if it, ok := ts.Type.(*ast.InterfaceType); ok {
			for _, m := range it.Methods.List {
				for _, name := range m.Names {
					ops[name.Name] = false
				}
			}
		}
		return false
	})
	if len(ops) == 0 {
		t.Fatal("api.gen.go declares no StrictServerInterface method: the check would pass having read nothing")
	}
	return ops
}

// codeLines is the set of lines in src that hold a token other than a comment.
func codeLines(src []byte) map[int]bool {
	lines := map[int]bool{}
	fset := token.NewFileSet()
	file := fset.AddFile("", fset.Base(), len(src))
	var s scanner.Scanner
	s.Init(file, src, nil, 0)
	for {
		pos, tok, _ := s.Scan()
		if tok == token.EOF {
			return lines
		}
		lines[file.Line(pos)] = true
	}
}

// handlerSizes measures, in one file, every method named like an operation: its code lines.
func handlerSizes(t *testing.T, name string, ops map[string]bool) map[string]int {
	t.Helper()
	fset := token.NewFileSet()
	f, src := parseHere(t, fset, name)
	code := codeLines(src)
	sizes := map[string]int{}
	for _, decl := range f.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Recv == nil || fn.Body == nil {
			continue
		}
		if _, isOp := ops[fn.Name.Name]; !isOp {
			continue
		}
		n := 0
		for line := fset.Position(fn.Body.Lbrace).Line + 1; line < fset.Position(fn.Body.Rbrace).Line; line++ {
			if code[line] {
				n++
			}
		}
		sizes[fn.Name.Name] = n
	}
	return sizes
}

func TestHandlersStayShort(t *testing.T) {
	t.Parallel()
	ops := operations(t)
	files, err := fs.Glob(here, "*.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range files {
		if strings.HasSuffix(name, "_test.go") || name == "api.gen.go" {
			continue
		}
		for op, n := range handlerSizes(t, name, ops) {
			ops[op] = true
			if n > maxHandlerLines {
				t.Errorf("%s: handler %s has %d code lines, over %d: move the work into its service", name, op, n, maxHandlerLines)
			}
		}
	}
	for op, found := range ops {
		if !found {
			t.Errorf("no handler for operation %s in this package", op)
		}
	}
}
