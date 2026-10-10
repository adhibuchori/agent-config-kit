// Tests that the payload core stays behind the transport (AGENTS.md Rule 29): only internal/httpapi
// and cmd/ import internal/payload, so no handler, service or store ever sees an envelope, and the
// core itself imports no net/http.

package payload_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path"
	"strconv"
	"strings"
	"testing"
)

// mayImport says whether the Go files of dir may import internal/payload.
func mayImport(dir string) bool {
	return dir == "internal/payload" || dir == "internal/httpapi" || dir == "cmd" || strings.HasPrefix(dir, "cmd/")
}

func modulePath(t *testing.T, module fs.FS) string {
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

// imports lists the import paths of one Go file of the module.
func imports(module fs.FS, name string) ([]string, error) {
	src, err := fs.ReadFile(module, name)
	if err != nil {
		return nil, err
	}
	f, err := parser.ParseFile(token.NewFileSet(), name, src, parser.ImportsOnly)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(f.Imports))
	for _, imp := range f.Imports {
		p, err := strconv.Unquote(imp.Path.Value)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}

func skipped(name string, d fs.DirEntry) bool {
	return d.IsDir() && name != "." && (strings.HasPrefix(d.Name(), ".") || d.Name() == "testdata" || d.Name() == "vendor")
}

func TestOnlyTheTransportImportsPayload(t *testing.T) {
	t.Parallel()
	module := os.DirFS("../..")
	core := modulePath(t, module) + "/internal/payload"
	read := 0
	err := fs.WalkDir(module, ".", func(name string, d fs.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case skipped(name, d):
			return fs.SkipDir
		case d.IsDir() || !strings.HasSuffix(name, ".go"):
			return nil
		}
		paths, err := imports(module, name)
		read++
		dir := path.Dir(name)
		for _, p := range paths {
			if p == core && !mayImport(dir) {
				t.Errorf("%s imports internal/payload; only internal/httpapi and cmd/ may (AGENTS.md Rule 29)", name)
			}
			if p == "net/http" && dir == "internal/payload" {
				t.Errorf("%s imports net/http; the payload core never sees HTTP", name)
			}
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	if read == 0 {
		t.Fatal("read no Go file: the check would pass having read nothing")
	}
}
