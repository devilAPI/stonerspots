package photos

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"runtime/debug"

	"github.com/disintegration/imaging"
	"github.com/gen2brain/avif" // AVIF via libavif compiled to WASM (no cgo in release builds)
	"golang.org/x/image/webp"
)

const (
	MaxUploadBytes = 8 << 20
	fullMaxEdge    = 1600
	thumbMaxEdge   = 400
	jpegQuality    = 85
)

var (
	ErrTooLarge    = errors.New("photo too large")
	ErrUnsupported = errors.New("unsupported image type")
)

// Normalize reads at most maxBytes from r, verifies it is a JPEG/PNG/WebP/AVIF by
// content (not by any client-supplied type), applies EXIF orientation and
// re-encodes it as metadata-free JPEG: full (long edge <= 1600) and thumb
// (long edge <= 400). w and h are the dimensions of full. It works in the
// process-wide decode slots (see decodelimit.go): ErrBusy, or ctx's error,
// when none frees up in time.
func Normalize(ctx context.Context, r io.Reader, maxBytes int64) (full, thumb []byte, w, h int, err error) {
	err = withDecoded(ctx, r, maxBytes, func(img image.Image, orient int) error {
		fullImg := orientImage(fit(img, fullMaxEdge), orient)
		thumbImg := fit(fullImg, thumbMaxEdge)
		if full, err = encodeJPEG(fullImg); err != nil {
			return err
		}
		if thumb, err = encodeJPEG(thumbImg); err != nil {
			return err
		}
		b := fullImg.Bounds()
		w, h = b.Dx(), b.Dy()
		return nil
	})
	if err != nil {
		return nil, nil, 0, 0, err
	}
	return full, thumb, w, h, nil
}

// AvatarEdge is the width and height of a stored avatar.
const AvatarEdge = 384

// NormalizeAvatar is Normalize for a profile picture: same limits and
// accepted types, then centre-cropped to a square and scaled to
// AvatarEdge x AvatarEdge (small images are scaled up), as metadata-free JPEG.
func NormalizeAvatar(ctx context.Context, r io.Reader, maxBytes int64) (out []byte, err error) {
	err = withDecoded(ctx, r, maxBytes, func(img image.Image, orient int) error {
		sq := orientImage(imaging.Fill(img, AvatarEdge, AvatarEdge, imaging.Center, imaging.Lanczos), orient)
		out, err = encodeJPEG(sq)
		return err
	})
	return out, err
}

// imgFormat is an accepted upload format, recognised by its magic bytes.
type imgFormat int

const (
	formatUnknown imgFormat = iota
	formatJPEG
	formatPNG
	formatWebP
	formatAVIF
)

// sniff recognises JPEG, PNG, WebP and AVIF by their first bytes. Anything
// else (TIFF, BMP, GIF, HEIC, ...) is formatUnknown and is never handed to
// a decoder.
func sniff(b []byte) imgFormat {
	switch {
	case len(b) >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF:
		return formatJPEG
	case len(b) >= 8 && string(b[:8]) == "\x89PNG\r\n\x1a\n":
		return formatPNG
	case len(b) >= 16 && string(b[:4]) == "RIFF" && string(b[8:12]) == "WEBP" && string(b[12:15]) == "VP8":
		return formatWebP
	case isAVIF(b):
		return formatAVIF
	}
	return formatUnknown
}

// isAVIF: an ISO-BMFF file whose leading ftyp box names "avif" as its major
// or one of its compatible brands. (Image sequences, "avis" only, are not
// accepted; see checkAVIF.)
func isAVIF(b []byte) bool {
	if len(b) < 16 || string(b[4:8]) != "ftyp" {
		return false
	}
	size := binary.BigEndian.Uint32(b[:4])
	if size < 16 || size > 4096 || int(size) > len(b) || size%4 != 0 {
		return false
	}
	if string(b[8:12]) == "avif" { // major brand; b[12:16] is the minor version
		return true
	}
	for i := 16; i+4 <= int(size); i += 4 {
		if string(b[i:i+4]) == "avif" {
			return true
		}
	}
	return false
}

// codec is the decoder of one format, called directly: never through the
// image package's registry, which imports (imaging) fill with TIFF, BMP and
// GIF decoders.
type codec struct {
	config func(io.Reader) (image.Config, error)
	decode func(io.Reader) (image.Image, error)
}

var codecs = map[imgFormat]codec{
	formatJPEG: {jpeg.DecodeConfig, jpeg.Decode},
	formatPNG:  {png.DecodeConfig, png.Decode},
	formatWebP: {webp.DecodeConfig, webp.Decode},
	formatAVIF: {avif.DecodeConfig, func(r io.Reader) (image.Image, error) { return avif.Decode(r) }},
}

// header is what is known about an upload from its first bytes.
type header struct {
	format imgFormat
	cfg    image.Config
}

// readHeader recognises the format of head (the first bytes of an upload,
// complete says whether that is all of it) and reads its dimensions. ok is
// false when head is too short for the dimensions and more data follows.
func readHeader(head []byte, complete bool) (h header, ok bool, err error) {
	h.format = sniff(head)
	c, known := codecs[h.format]
	if !known {
		return h, false, ErrUnsupported
	}
	h.cfg, err = c.config(bytes.NewReader(head))
	if err != nil {
		if complete {
			return h, false, ErrUnsupported
		}
		return h, false, nil
	}
	if h.cfg.Width <= 0 || h.cfg.Height <= 0 || int64(h.cfg.Width)*int64(h.cfg.Height) > maxPixels {
		return h, false, ErrUnsupported
	}
	return h, true, nil
}

// withDecoded reads an upload of at most maxBytes from r, checks its format
// by its magic bytes and its size, takes the decode slots it needs,
// decodes it with its format's own decoder and calls fn with the image and
// its EXIF orientation (1-8, 0 = none), still holding the slots.
//
// Only the first sniffLen bytes are read before waiting for the slots, so
// waiting uploads hold little memory.
func withDecoded(ctx context.Context, r io.Reader, maxBytes int64, fn func(image.Image, int) error) error {
	r = io.LimitReader(r, maxBytes+1)
	head := make([]byte, min(sniffLen, maxBytes+1))
	n, err := io.ReadFull(r, head)
	complete := err == io.EOF || err == io.ErrUnexpectedEOF
	if err != nil && !complete {
		return err
	}
	head = head[:n]
	if int64(n) > maxBytes {
		return ErrTooLarge
	}
	hdr, known, err := readHeader(head, complete)
	if err != nil {
		return err
	}
	slots := maxConcurrentDecodes // dimensions not in the first bytes: assume the worst
	if known {
		if slots = slotsFor(hdr.format, head, hdr.cfg); slots == 0 {
			return ErrUnsupported
		}
	}

	release, err := acquireDecodeSlots(ctx, slots)
	if err != nil {
		return err
	}
	defer release()
	if inSlot != nil {
		inSlot()
	}
	err = decodeAndRun(r, head, complete, maxBytes, slots, fn)
	// Give the decode's memory back before the next one can start: else the
	// GC lets the heap grow to twice what the last decodes had live, and
	// the slots no longer bound it (measured: 8 PNGs of ~255 MB each, two
	// at a time, peaked at ~970 MB RSS without this, ~500 MB with it).
	debug.FreeOSMemory()
	return err
}

// decodeAndRun is the part of withDecoded that runs in the decode slots.
func decodeAndRun(r io.Reader, head []byte, complete bool, maxBytes int64, slots int, fn func(image.Image, int) error) error {
	data := head
	if !complete {
		var buf bytes.Buffer
		buf.Grow(int(min(maxBytes+1, 2*sniffLen)))
		buf.Write(head)
		if _, err := buf.ReadFrom(r); err != nil {
			return err
		}
		data = buf.Bytes()
	}
	if int64(len(data)) > maxBytes {
		return ErrTooLarge
	}
	// the whole file now: same checks, and the cost must fit the slots held
	hdr, _, err := readHeader(data, true)
	if err != nil {
		return err
	}
	if s := slotsFor(hdr.format, data, hdr.cfg); s == 0 || s > slots {
		return ErrUnsupported
	}
	if hdr.format == formatAVIF && checkAVIF(data) != nil {
		return ErrUnsupported
	}
	img, err := codecs[hdr.format].decode(bytes.NewReader(data))
	if err != nil {
		return ErrUnsupported
	}
	// the header and the image data must agree
	if b := img.Bounds(); b.Dx() != hdr.cfg.Width || b.Dy() != hdr.cfg.Height {
		return ErrUnsupported
	}
	orient := 0
	if hdr.format == formatJPEG {
		orient = jpegOrientation(data)
	}
	return fn(img, orient)
}

// jpegOrientation returns the EXIF orientation (1-8) of a JPEG, 0 when it
// has none or it cannot be read.
func jpegOrientation(b []byte) (o int) {
	jpegSegments(b, func(marker byte, seg []byte) bool {
		if marker == 0xE1 && len(seg) >= 6 && string(seg[:6]) == "Exif\x00\x00" {
			o = exifOrientation(seg[6:])
			return false
		}
		return true
	})
	return o
}

// exifOrientation reads tag 0x0112 from IFD0 of a TIFF-structured EXIF
// block.
func exifOrientation(t []byte) int {
	if len(t) < 8 {
		return 0
	}
	var bo binary.ByteOrder
	switch string(t[:2]) {
	case "II":
		bo = binary.LittleEndian
	case "MM":
		bo = binary.BigEndian
	default:
		return 0
	}
	off := int(bo.Uint32(t[4:8]))
	if off < 8 || off+2 > len(t) {
		return 0
	}
	n := int(bo.Uint16(t[off : off+2]))
	for i := 0; i < n; i++ {
		e := off + 2 + 12*i
		if e+12 > len(t) {
			return 0
		}
		if bo.Uint16(t[e:e+2]) != 0x0112 {
			continue
		}
		if v := int(bo.Uint16(t[e+8 : e+10])); v >= 1 && v <= 8 {
			return v
		}
		return 0
	}
	return 0
}

// orientImage applies EXIF orientation o (the same mapping as imaging's
// AutoOrientation). It is applied after scaling down: on the small image
// it costs little memory, and the result is the same.
func orientImage(img image.Image, o int) image.Image {
	switch o {
	case 2:
		return imaging.FlipH(img)
	case 3:
		return imaging.Rotate180(img)
	case 4:
		return imaging.FlipV(img)
	case 5:
		return imaging.Transpose(img)
	case 6:
		return imaging.Rotate270(img)
	case 7:
		return imaging.Transverse(img)
	case 8:
		return imaging.Rotate90(img)
	}
	return img
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
