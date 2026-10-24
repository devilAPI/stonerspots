package photos_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"strings"
	"testing"

	"github.com/gen2brain/avif"

	"stonerspots/backend/internal/photos"
	"stonerspots/backend/internal/testutil"
)

func avifBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x % 256), uint8(y % 256), 120, 255})
		}
	}
	var buf bytes.Buffer
	if err := avif.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// Phones and browsers increasingly save/share AVIF; it must upload like JPEG.
func TestUploadAVIFIsAcceptedAndStoredAsJPEG(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/avif", avifBytes(t, 320, 240))
	if rec.Code != 201 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var r resp
	json.Unmarshal(rec.Body.Bytes(), &r)
	var key string
	var w, h int
	if err := e.db.QueryRow("SELECT `key`, width, height FROM photos WHERE id=?", r.ID).Scan(&key, &w, &h); err != nil {
		t.Fatal(err)
	}
	if w != 320 || h != 240 || !strings.HasSuffix(key, ".jpg") {
		t.Fatalf("stored w=%d h=%d key=%q", w, h, key)
	}
}

func TestAVIFContentTypeLieIsStillRejected(t *testing.T) {
	e := setup(t)
	rec := upload(t, e, testutil.Token(t, e.uid), "image/avif", []byte("this is not an image at all"))
	if rec.Code != 415 || errCode(rec) != "unsupported_type" {
		t.Fatalf("status %d %s", rec.Code, rec.Body)
	}
}

func TestNormalizeAcceptsASmallAVIF(t *testing.T) {
	data := avifBytes(t, 64, 64)
	if _, _, _, _, err := photos.Normalize(bytes.NewReader(data), photos.MaxUploadBytes); err != nil {
		t.Fatalf("small avif should work: %v", err)
	}
}
