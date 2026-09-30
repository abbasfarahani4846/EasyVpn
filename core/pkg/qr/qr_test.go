package qr

import (
	"bytes"
	"image/png"
	"testing"

	"github.com/makiuchi-d/gozxing"
	"github.com/makiuchi-d/gozxing/qrcode"
)

func TestDecodeRoundTrip(t *testing.T) {
	link := "vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.ir:443?type=xhttp&security=tls&mode=stream-up#🇺🇸 USA"
	m, err := qrcode.NewQRCodeWriter().Encode(link, gozxing.BarcodeFormat_QR_CODE, 400, 400, nil)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, m); err != nil {
		t.Fatal(err)
	}
	got, err := Decode(buf.Bytes())
	if err != nil || got != link {
		t.Fatalf("decode: %q %v", got, err)
	}
	if _, err := Decode([]byte("not an image")); err == nil {
		t.Fatal("expected error for non-image")
	}
}
