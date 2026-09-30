// Package qr decodes QR codes from images (screenshots, photos). It runs in
// the Go core so "import from image" works on every platform, including
// desktop where no camera scanner is available.
package qr

import (
	"bytes"
	"fmt"
	"image"
	_ "image/gif"  // register decoders
	_ "image/jpeg" // register decoders
	_ "image/png"  // register decoders

	"github.com/makiuchi-d/gozxing"
	"github.com/makiuchi-d/gozxing/qrcode"
	_ "golang.org/x/image/webp" // register decoders
)

// Decode returns the text of the QR code in the image bytes.
func Decode(data []byte) (string, error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return "", fmt.Errorf("not a supported image (png, jpeg, gif, webp): %w", err)
	}
	return DecodeImage(img)
}

// DecodeImage decodes a QR code from an image.
func DecodeImage(img image.Image) (string, error) {
	bmp, err := gozxing.NewBinaryBitmapFromImage(img)
	if err != nil {
		return "", err
	}
	hints := map[gozxing.DecodeHintType]interface{}{
		gozxing.DecodeHintType_TRY_HARDER:    true,
		gozxing.DecodeHintType_CHARACTER_SET: "UTF-8",
	}
	res, err := qrcode.NewQRCodeReader().Decode(bmp, hints)
	if err != nil {
		return "", fmt.Errorf("no QR code found in the image")
	}
	return res.GetText(), nil
}
