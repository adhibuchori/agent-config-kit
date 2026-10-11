// The one cipher on the wire: AES-256-GCM with a fresh 96-bit nonce per seal and the 128-bit tag after
// the ciphertext. The additional data is never sent; it binds a ciphertext to its route, so an
// envelope lifted from one route fails to open on another instead of decrypting into a plausible body.

package payload

import (
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"slices"
)

const (
	keySize   = 32 // AES-256
	nonceSize = 12 // the nonce length GCM is specified for; any other is refused
)

// ErrKeySize is NewKey's answer to key material that is not exactly 32 bytes.
var ErrKeySize = errors.New("payload: an AES-256-GCM key is exactly 32 bytes")

// Key is an AES-256-GCM key. NewKey and DeriveKey make one; the zero Key seals nothing.
type Key struct{ aead cipher.AEAD }

// NewKey turns exactly 32 bytes into a key. Shorter or longer material is refused here, at startup,
// instead of failing at the first envelope on the other side of the wire.
func NewKey(raw []byte) (Key, error) {
	block, err := aes.NewCipher(raw)
	if err != nil || len(raw) != keySize {
		return Key{}, ErrKeySize
	}
	// The AEAD draws each nonce from crypto/rand and puts it before its output, so no caller can
	// choose, and so reuse, one. It fails only for a block size other than AES's.
	aead, err := cipher.NewGCMWithRandomNonce(block)
	return Key{aead: aead}, err
}

// seal encrypts plain bound to aad, and returns the fresh nonce and the ciphertext with its tag.
func (k Key) seal(plain, aad []byte) (nonce, sealed []byte) {
	out := k.aead.Seal(nil, nil, plain, aad) //nolint:gosec // G407: the AEAD draws its own nonce; nil is the empty one.
	return out[:nonceSize], out[nonceSize:]
}

// open verifies and decrypts. One answer for a wrong key, a tampered body and a foreign AAD alike:
// saying which one failed tells a prober which half of a guess was right.
func (k Key) open(nonce, sealed, aad []byte) ([]byte, error) {
	if len(nonce) != nonceSize {
		return nil, fail(Rejected, "the nonce is %d bytes, not %d", len(nonce), nonceSize)
	}
	plain, err := k.aead.Open(nil, nil, slices.Concat(nonce, sealed), aad)
	if err != nil {
		return nil, fail(Rejected, "the tag did not verify")
	}
	return plain, nil
}
