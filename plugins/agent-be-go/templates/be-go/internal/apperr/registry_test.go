// Tests that every registered code is declared once, raised somewhere, and never minted elsewhere.

package apperr_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"maps"
	"os"
	"path"
	"regexp"
	"slices"
	"strings"
	"testing"

	"example.com/service/internal/apperr"
)

// The module root, seen from this package's folder.
const root = "../.."

var (
	codeName  = regexp.MustCompile(`^[A-Z][A-Z0-9_]*$`)
	generated = regexp.MustCompile(`(?m)^// Code generated .* DO NOT EDIT\.$`)
	module    = os.DirFS(root)
)

// isRegistryFile reports whether a file of this package declares codes: codes.go, and any other
// *codes.go a module adds.
func isRegistryFile(name string) bool {
	return strings.HasSuffix(name, "codes.go") && !strings.HasSuffix(name, "_test.go")
}

// registry reads the code variables from their home, the *codes.go files, never from a copy: var
// name to code name.
func registry(t *testing.T) map[string]string {
	t.Helper()
	files, err := fs.Glob(module, "internal/apperr/*codes.go")
	if err != nil {
		t.Fatal(err)
	}
	vars := map[string]string{}
	for _, name := range files {
		codeVars(parse(t, token.NewFileSet(), name), vars)
	}
	if len(vars) == 0 {
		t.Fatal("no registered code found in *codes.go: the check would pass having read nothing")
	}
	return vars
}

func parse(t *testing.T, fset *token.FileSet, name string) *ast.File {
	t.Helper()
	src, err := fs.ReadFile(module, name)
	if err != nil {
		t.Fatal(err)
	}
	f, err := parser.ParseFile(fset, name, src, parser.SkipObjectResolution)
	if err != nil {
		t.Fatal(err)
	}
	return f
}

// registeredNames are the names apperr.Registered() lists, sorted.
func registeredNames() []string {
	names := make([]string, 0, len(apperr.Registered()))
	for _, c := range apperr.Registered() {
		names = append(names, c.Name())
	}
	return slices.Sorted(slices.Values(names))
}

func modulePath(t *testing.T) string {
	t.Helper()
	data, err := fs.ReadFile(module, "go.mod")
	if err != nil {
		t.Fatal(err)
	}
	for line := range strings.Lines(string(data)) {
		if mod, ok := strings.CutPrefix(line, "module "); ok {
			return strings.TrimSpace(mod)
		}
	}
	t.Fatal("go.mod has no module line")
	return ""
}

func skipped(name string, d fs.DirEntry) bool {
	if d.IsDir() {
		return name != "." && (d.Name() == "testdata" || d.Name() == "vendor" || strings.HasPrefix(d.Name(), "."))
	}
	return !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") ||
		(path.Dir(name) == "internal/apperr" && isRegistryFile(d.Name()))
}

// sources lists the module's hand-written, non-test Go files outside the registry files.
func sources(t *testing.T) []string {
	t.Helper()
	var out []string
	err := fs.WalkDir(module, ".", func(name string, d fs.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case skipped(name, d) && d.IsDir():
			return fs.SkipDir
		case d.IsDir() || skipped(name, d):
			return nil
		}
		src, err := fs.ReadFile(module, name)
		if err == nil && !generated.Match(src) {
			out = append(out, name)
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

// TestEveryCodeIsRegisteredAndRaised fails on a code the registry and Registered() disagree on, a
// name that is not UPPER_SNAKE, a code nothing outside the registry raises (the spec promises it
// and nothing sends it), and a Code literal built outside this package (a code nobody registered).
func TestEveryCodeIsRegisteredAndRaised(t *testing.T) {
	t.Parallel()
	vars := registry(t)
	declared := slices.Sorted(maps.Values(vars))
	if listed := registeredNames(); !slices.Equal(declared, listed) {
		t.Errorf("Registered() lists %v; *codes.go declares %v", listed, declared)
	}
	used := map[string]bool{}
	fset := token.NewFileSet()
	pkgPath := modulePath(t) + "/internal/apperr"
	for _, name := range sources(t) {
		f := parse(t, fset, name)
		inPkg := path.Dir(name) == "internal/apperr"
		ast.Walk(&scan{t: t, fset: fset, used: used, local: localName(f, pkgPath), inPkg: inPkg}, f)
	}
	for ident, name := range vars {
		if !used[ident] {
			t.Errorf("registered code %s (%s) is never raised outside the registry", name, ident)
		}
	}
	for _, c := range apperr.Registered() {
		if !codeName.MatchString(c.Name()) || c.Status() < 400 || c.Title() == "" {
			t.Errorf("code %q: want an UPPER_SNAKE name, a 4xx or 5xx status and a title", c.Name())
		}
	}
}
