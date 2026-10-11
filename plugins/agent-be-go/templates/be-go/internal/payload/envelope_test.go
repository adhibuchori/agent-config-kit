// Tests for the wire format: the AAD strings, the exact envelope shape, and the freshness window.

package payload

import (
	"strings"
	"testing"
	"time"
)

func TestAADsAreTheWireStrings(t *testing.T) {
	t.Parallel()
	if got := string(RequestAAD("post", "/api/notes/:id")("k1", 5)); got != "1.POST./api/notes/:id.k1.5" {
		t.Errorf("request AAD %q", got)
	}
	if got := string(ResponseAAD(201, "/api/notes")("ecdh", 1767225600000)); got != "1.201./api/notes.ecdh.1767225600000" {
		t.Errorf("response AAD %q", got)
	}
}

const goodEnvelope = `{"v":1,"alg":"A256GCM","kid":"k1","iv":"aa","ct":"bb","ts":1767225600000}`

func TestParseEnvelopeReadsVersion1(t *testing.T) {
	t.Parallel()
	e, err := parseEnvelope([]byte(goodEnvelope))
	want := envelope{V: 1, Alg: "A256GCM", Kid: "k1", IV: "aa", CT: "bb", TS: 1767225600000}
	if err != nil || e != want {
		t.Fatalf("got %+v, %v", e, err)
	}
}

func TestParseEnvelopeRefusesAnyOtherShapeAsNotSealed(t *testing.T) {
	t.Parallel()
	swap := func(old, repl string) string { return strings.Replace(goodEnvelope, old, repl, 1) }
	for _, raw := range []string{
		`not json`, `[]`, `null`, `{}`,
		swap(`"v":1`, `"V":1`), swap(`"v":1`, `"v":2`), swap(`"v":1`, `"v":"1"`), swap(`"v":1`, `"v":1.0`),
		swap(`"A256GCM"`, `"A128GCM"`), swap(`"kid":"k1",`, ``), swap(`"kid":"k1"`, `"kid":null`),
		swap(`"iv":"aa"`, `"iv":7`), swap(`"ct":"bb"`, `"ct":["bb"]`),
		swap(`1767225600000`, `1767225600000.5`), swap(`1767225600000`, `"1767225600000"`),
		swap(`1767225600000`, `9007199254740992`), swap(`1767225600000`, `-9007199254740992`),
	} {
		_, err := parseEnvelope([]byte(raw))
		if CodeOf(err) != Required || err == nil {
			t.Errorf("%s: got %v, want %s", raw, err, Required)
		}
	}
}

func TestFreshnessIsTwoMinutesEitherWay(t *testing.T) {
	t.Parallel()
	ts := at.UnixMilli()
	for _, tt := range []struct {
		skew time.Duration
		want bool
	}{
		{0, true}, {MaxSkew, true}, {-MaxSkew, true}, {MaxSkew + time.Millisecond, false}, {-MaxSkew - time.Millisecond, false},
	} {
		if got := fresh(ts, at.Add(tt.skew)); got != tt.want {
			t.Errorf("now = ts%+v: fresh %v, want %v", tt.skew, got, tt.want)
		}
	}
}
