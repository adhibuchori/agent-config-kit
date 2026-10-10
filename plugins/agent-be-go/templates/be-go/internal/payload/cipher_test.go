// Tests for the cipher: AES-256 only, a fresh nonce per seal, and one refusal for every failure.

package payload

import (
	"bytes"
	"errors"
	"slices"
	"testing"
)

func TestNewKeyTakesExactly32Bytes(t *testing.T) {
	t.Parallel()
	for _, n := range []int{0, 5, 16, 24, 31, 33} {
		if _, err := NewKey(make([]byte, n)); !errors.Is(err, ErrKeySize) {
			t.Errorf("%d bytes: got %v, want ErrKeySize", n, err)
		}
	}
	if _, err := NewKey(make([]byte, 32)); err != nil {
		t.Fatal(err)
	}
}

func TestSealDrawsAFreshNonceEachTime(t *testing.T) {
	t.Parallel()
	key := mustKey(t, "cipher")
	n1, s1 := key.seal([]byte(`{}`), []byte("aad"))
	n2, s2 := key.seal([]byte(`{}`), []byte("aad"))
	if len(n1) != nonceSize || bytes.Equal(n1, n2) || bytes.Equal(s1, s2) {
		t.Fatalf("nonces %x and %x", n1, n2)
	}
	if len(s1) != len(`{}`)+16 {
		t.Fatalf("want the ciphertext and a 16-byte tag, got %d bytes", len(s1))
	}
}

func TestOpenRefusesEveryFailureTheSameWay(t *testing.T) {
	t.Parallel()
	key := mustKey(t, "cipher")
	aad := []byte("1.POST./api/notes.k1.0")
	nonce, sealed := key.seal([]byte(`{"a":1}`), aad)
	if plain, err := key.open(nonce, sealed, aad); err != nil || string(plain) != `{"a":1}` {
		t.Fatalf("got %q, %v", plain, err)
	}
	tampered := slices.Clone(sealed)
	tampered[0] ^= 1
	for name, try := range map[string]func() error{
		"short nonce": func() error { _, err := key.open(nonce[:11], sealed, aad); return err },
		"tampered":    func() error { _, err := key.open(nonce, tampered, aad); return err },
		"another aad": func() error { _, err := key.open(nonce, sealed, []byte("1.PUT./api/notes.k1.0")); return err },
		"another key": func() error { _, err := mustKey(t, "other").open(nonce, sealed, aad); return err },
	} {
		if err := try(); CodeOf(err) != Rejected || err == nil {
			t.Errorf("%s: got %v, want %s", name, err, Rejected)
		}
	}
}
