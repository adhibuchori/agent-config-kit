// Tests for the switch: the environment wins, then the committed file, then strict; off never in
// production; a typo is refused instead of read as strict.

package payload

import "testing"

func TestResolveMode(t *testing.T) {
	t.Parallel()
	tests := []struct {
		env, committed string
		production     bool
		want           mode
		ok             bool
	}{
		{"", "strict", false, strict, true},
		{"", "off", false, off, true},
		{"", "", false, strict, true},
		{" OFF ", "strict", false, off, true},
		{"strict", "off", true, strict, true},
		{"", " Strict ", true, strict, true},
		{"", "off", true, "", false},
		{"off", "strict", true, "", false},
		{"maybe", "strict", false, "", false},
		{"", "stirct", false, "", false},
	}
	for _, tt := range tests {
		got, err := resolveMode(tt.env, tt.committed, tt.production)
		if got != tt.want || (err == nil) != tt.ok {
			t.Errorf("resolveMode(%q, %q, %v) = %q, %v", tt.env, tt.committed, tt.production, got, err)
		}
	}
}
