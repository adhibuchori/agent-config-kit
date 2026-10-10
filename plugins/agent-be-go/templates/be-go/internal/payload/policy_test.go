// Tests for the policies, the codes, and the registry accessor.

package payload

import (
	"errors"
	"fmt"
	"testing"
)

func TestEachPolicySealsTheSidesItNames(t *testing.T) {
	t.Parallel()
	for p, want := range map[Policy][2]bool{
		PolicyStrict: {true, true}, PolicyResponseOnly: {false, true}, PolicyRequestOnly: {true, false}, PolicyNone: {false, false},
	} {
		if got := [2]bool{p.SealsRequest(), p.SealsResponse()}; got != want {
			t.Errorf("%s seals (request, response) %v, want %v", p, got, want)
		}
	}
}

func TestRegistryIsACopy(t *testing.T) {
	t.Parallel()
	first := Registry()
	if len(first) == 0 {
		t.Fatal("registry.gen.go lists no endpoint")
	}
	first[0].Route = "/changed"
	if Registry()[0] == first[0] {
		t.Fatal("a caller changed the registry")
	}
}

func TestCodeOfFindsThePayloadFailure(t *testing.T) {
	t.Parallel()
	err := fail(Expired, "ts %d", 7)
	if err.Error() != "ENVELOPE_EXPIRED: ts 7" || CodeOf(err) != Expired {
		t.Fatalf("got %q", err.Error())
	}
	if CodeOf(fmt.Errorf("open: %w", fail(Rejected, "tag"))) != Rejected || CodeOf(errors.New("other")) != Malformed {
		t.Fatal("CodeOf must read the chain, and answer Malformed for any other error")
	}
}
