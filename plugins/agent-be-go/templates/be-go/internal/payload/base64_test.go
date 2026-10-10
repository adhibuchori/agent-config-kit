// Tests that the codec writes unpadded base64url and reads what every other copy reads.

package payload

import (
	"bytes"
	"testing"
)

func TestEncodeIsUnpaddedBase64URL(t *testing.T) {
	t.Parallel()
	if got := Encode([]byte{0xfb, 0xff}); got != "-_8" {
		t.Fatalf("got %q", got)
	}
}

func TestDecodeReadsBothAlphabetsPaddingAndWhitespace(t *testing.T) {
	t.Parallel()
	for _, in := range []string{"-_8", "+/8=", " +/8= \n", "-_\t8"} {
		got, err := Decode(in)
		if err != nil || !bytes.Equal(got, []byte{0xfb, 0xff}) {
			t.Errorf("Decode(%q) = %x, %v", in, got, err)
		}
	}
}

func TestDecodeRefusesWhatIsNotBase64(t *testing.T) {
	t.Parallel()
	// Padding is all or nothing, and only at the end, as atob reads it.
	for _, in := range []string{"*", "a", "+/=", "+/=8", "+/8==="} {
		if _, err := Decode(in); err == nil {
			t.Errorf("Decode(%q) accepted", in)
		}
	}
}
