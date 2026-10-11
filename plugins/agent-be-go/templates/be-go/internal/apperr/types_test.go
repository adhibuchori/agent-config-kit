// Tests for the problem-type base check and the type a code mints.

package apperr_test

import (
	"errors"
	"testing"

	"example.com/service/internal/apperr"
)

func TestCheckTypeBase(t *testing.T) {
	t.Parallel()
	tests := []struct {
		base       string
		production bool
		ok         bool
	}{
		{"https://api.example.com/problems/", true, true},
		{"https://api.example.com/", false, true},
		{"https://example.invalid/problems/", false, true},
		{"https://example.invalid/problems/", true, false},
		{"http://api.example.com/problems/", false, false},
		{"/problems/", false, false},
		{"https://api.example.com/problems", false, false},
		{"https://api.example.com/problems/?v=1", false, false},
		{"https://api.example.com/problems/#x", false, false},
		{"https://user@api.example.com/problems/", false, false},
		{"https://API.example.com/problems/", false, false},
		{"https://api.example.com/a/../problems/", false, false},
		{"https://api.example.com/%zz/", false, false},
	}
	for _, tt := range tests {
		err := apperr.CheckTypeBase(tt.base, tt.production)
		if (err == nil) != tt.ok {
			t.Errorf("CheckTypeBase(%q, production=%v) = %v, want ok=%v", tt.base, tt.production, err, tt.ok)
		}
	}
	if err := apperr.CheckTypeBase("https://example.invalid/problems/", true); !errors.Is(err, apperr.ErrPlaceholderBase) {
		t.Errorf("the placeholder in production: got %v, want ErrPlaceholderBase", err)
	}
}

func TestTheShippedBaseIsWellFormed(t *testing.T) {
	t.Parallel()
	if err := apperr.CheckTypeBase(apperr.TypeBase, false); err != nil {
		t.Fatal(err)
	}
	if got := apperr.NotFound.Type(); got != apperr.TypeBase+"NOT_FOUND" {
		t.Fatalf("got %q", got)
	}
}
