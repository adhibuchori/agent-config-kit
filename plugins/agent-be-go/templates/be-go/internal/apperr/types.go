// Problem types: the base every problem's type starts with, and the check main runs on it.

package apperr

import (
	"errors"
	"fmt"
	"net/url"
	"path"
	"strings"
)

// TypeBase is this API's RFC 9457 problem-type base: a problem's type is TypeBase followed by its
// code. Set it once, before the first release, to an https URI under a domain the team controls,
// unique to this API and ending in "/". Clients key on the type, so the base never changes after
// that. api/openapi.yaml publishes the same value as x-problem-type-base on Problem.type.
const TypeBase = "https://example.invalid/problems/"

// ErrPlaceholderBase is CheckTypeBase's answer in production while the base is still the
// placeholder: a host under .invalid never resolves, so clients would keep identities that point
// nowhere.
var ErrPlaceholderBase = errors.New("the problem type base is still the .invalid placeholder")

// Type is the problem type URI of c.
func (c Code) Type() string { return TypeBase + c.name }

// CheckTypeBase says why base cannot be a problem-type base, or nil when it can: an absolute https
// URI with a host, no user, query or fragment, a path ending in "/", and in normal form. In
// production a host under .invalid is refused as well. main runs it before the server starts.
func CheckTypeBase(base string, production bool) error {
	u, err := url.Parse(base)
	if err != nil {
		return fmt.Errorf("problem type base %q: %w", base, err)
	}
	var why string
	switch {
	case u.Scheme != "https" || u.Host == "":
		why = "is not an absolute https URI"
	case u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "":
		why = "carries a user, a query or a fragment"
	case !strings.HasSuffix(u.Path, "/"):
		why = `does not end in "/"`
	case u.String() != base || strings.ToLower(u.Host) != u.Host || strings.TrimSuffix(path.Clean(u.Path), "/")+"/" != u.Path:
		why = "is not in normal form"
	case production && strings.HasSuffix(u.Hostname(), ".invalid"):
		return fmt.Errorf("%w: set apperr.TypeBase and x-problem-type-base to this API's own base", ErrPlaceholderBase)
	default:
		return nil
	}
	return fmt.Errorf("problem type base %q %s", base, why)
}
