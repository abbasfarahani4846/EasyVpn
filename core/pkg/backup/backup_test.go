package backup

import (
	"bytes"
	"testing"
)

func TestRoundTripAndWrongPassphrase(t *testing.T) {
	data := []byte(`{"profiles":[{"name":"x"}]}`)
	blob, err := Encrypt(data, "correct horse")
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(blob, []byte("profiles")) {
		t.Fatal("plaintext leaked")
	}
	got, err := Decrypt(blob, "correct horse")
	if err != nil || !bytes.Equal(got, data) {
		t.Fatalf("decrypt: %v %s", err, got)
	}
	if _, err := Decrypt(blob, "wrong"); err != ErrBadPassphrase {
		t.Fatalf("want ErrBadPassphrase, got %v", err)
	}
	blob[len(blob)-1] ^= 1 // tamper
	if _, err := Decrypt(blob, "correct horse"); err != ErrBadPassphrase {
		t.Fatalf("tamper not detected: %v", err)
	}
}
