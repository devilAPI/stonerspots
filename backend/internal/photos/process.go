package photos

import (
	"bytes"
	"errors"
	"image"
	"image/jpeg"
	"image/png"
	"io"

	"github.com/disintegration/imaging"
	_ "github.com/gen2brain/avif" // registers AVIF decoding (pure Go, no cgo)
	_ "golang.org/x/image/webp"   // registers WebP decoding
)

const (
	MaxUploadBytes = 8 << 20
	fullMaxEdge    = 1600
	thumbMaxEdge   = 400
	maxPixels      = 40_000_000 // decompression-bomb guard
	jpegQuality    = 85
)

var (
	ErrTooLarge    = errors.New("photo too large")
	ErrUnsupported = errors.New("unsupported image type")
)

// Normalize reads at most maxBytes from r, verifies it is a JPEG/PNG/WebP/AVIF by
// content (not by any client-supplied type), applies EXIF orientation and
// re-encodes it as metadata-free JPEG: full (long edge <= 1600) and thumb
// (long edge <= 400). w and h are the dimensions of full.
func Normalize(r io.Reader, maxBytes int64) (full, thumb []byte, w, h int, err error) {
	data, err := io.ReadAll(io.LimitReader(r, maxBytes+1))
	if err != nil {
		return nil, nil, 0, 0, err
	}
	if int64(len(data)) > maxBytes {
		return nil, nil, 0, 0, ErrTooLarge
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || (format != "jpeg" && format != "png" && format != "webp" && format != "avif") {
		return nil, nil, 0, 0, ErrUnsupported
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width*cfg.Height > maxPixels {
		return nil, nil, 0, 0, ErrUnsupported
	}
	img, err := imaging.Decode(bytes.NewReader(data), imaging.AutoOrientation(true))
	if err != nil {
		return nil, nil, 0, 0, ErrUnsupported
	}
	fullImg := fit(img, fullMaxEdge)
	thumbImg := fit(fullImg, thumbMaxEdge)
	if full, err = encodeJPEG(fullImg); err != nil {
		return nil, nil, 0, 0, err
	}
	if thumb, err = encodeJPEG(thumbImg); err != nil {
		return nil, nil, 0, 0, err
	}
	b := fullImg.Bounds()
	return full, thumb, b.Dx(), b.Dy(), nil
}

// fit scales down so the long edge is at most max; never upscales.
func fit(img image.Image, max int) image.Image {
	b := img.Bounds()
	if b.Dx() <= max && b.Dy() <= max {
		return img
	}
	if b.Dx() >= b.Dy() {
		return imaging.Resize(img, max, 0, imaging.Lanczos)
	}
	return imaging.Resize(img, 0, max, imaging.Lanczos)
}

func encodeJPEG(img image.Image) ([]byte, error) {
	// Flatten any alpha onto white; the JPEG encoder drops all metadata.
	flat := imaging.New(img.Bounds().Dx(), img.Bounds().Dy(), image.White)
	flat = imaging.Overlay(flat, img, image.Pt(0, 0), 1)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, flat, &jpeg.Options{Quality: jpegQuality}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

var _ = png.Decode // register PNG decoder
