// The go/ast helpers the registry test reads the module with.

package apperr_test

import (
	"go/ast"
	"go/token"
	"strconv"
	"testing"
)

// literalName is the name a Code{"NAME", ...} literal gives a var, or "" for any other value.
func literalName(v ast.Expr) string {
	cl, ok := v.(*ast.CompositeLit)
	if !ok || !isIdent(cl.Type, "Code") || len(cl.Elts) == 0 {
		return ""
	}
	lit, ok := cl.Elts[0].(*ast.BasicLit)
	if !ok {
		return ""
	}
	name, err := strconv.Unquote(lit.Value)
	if err != nil {
		return ""
	}
	return name
}

// codeVars maps each package-level var of one file that holds a Code literal to its code name.
func codeVars(f *ast.File, into map[string]string) {
	for _, decl := range f.Decls {
		gd, ok := decl.(*ast.GenDecl)
		if !ok || gd.Tok != token.VAR {
			continue
		}
		for _, spec := range gd.Specs {
			valueNames(spec, into)
		}
	}
}

func valueNames(spec ast.Spec, into map[string]string) {
	vs, ok := spec.(*ast.ValueSpec)
	if !ok {
		return
	}
	for i, v := range vs.Values {
		if name := literalName(v); name != "" {
			into[vs.Names[i].Name] = name
		}
	}
}

func isIdent(e ast.Expr, name string) bool {
	id, ok := e.(*ast.Ident)
	return ok && id.Name == name
}

// localName is the name a file gives the apperr import, or "" when it does not import it.
func localName(f *ast.File, pkgPath string) string {
	for _, imp := range f.Imports {
		if p, err := strconv.Unquote(imp.Path.Value); err != nil || p != pkgPath {
			continue
		}
		if imp.Name != nil {
			return imp.Name.Name
		}
		return "apperr"
	}
	return ""
}

// scan records the apperr identifiers one file names and reports any Code literal it builds.
type scan struct {
	t     *testing.T
	fset  *token.FileSet
	used  map[string]bool
	local string
	inPkg bool
}

func (s *scan) Visit(n ast.Node) ast.Visitor {
	switch x := n.(type) {
	case *ast.SelectorExpr:
		if s.local != "" && isIdent(x.X, s.local) {
			s.used[x.Sel.Name] = true
		}
	case *ast.CompositeLit:
		if sel, ok := x.Type.(*ast.SelectorExpr); ok && s.local != "" && isIdent(sel.X, s.local) && sel.Sel.Name == "Code" {
			s.t.Errorf("%s: builds an apperr.Code literal; raise a registered code", s.fset.Position(x.Pos()))
		}
	case *ast.Ident:
		if s.inPkg {
			s.used[x.Name] = true
		}
	}
	return s
}
