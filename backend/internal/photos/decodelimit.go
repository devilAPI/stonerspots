package photos

import (
	"context"
	"encoding/binary"
	"errors"
	"image"
	"image/color"
	"time"
)

// Decoding is what can take a home server down: a few hundred KB of PNG or
// AVIF can expand to hundreds of MB. Three limits keep the memory of all
// uploads together bounded, whatever the number of users or requests:
//
//   - maxPixels refuses large images before they are decoded;
//   - the decode slots: at most maxConcurrentDecodes images are decoded and
//     processed at once, process-wide (photos and avatars);
//   - each slot stands for decodeSlotBytes of memory, and an image whose
//     estimated peak (decodeCost) needs more takes both slots and runs
//     alone; one that would need more than all slots is refused.
//
// So the decodes together stay under maxConcurrentDecodes*decodeSlotBytes
// (600 MB). Requests wait for a slot holding only the first bytes of their
// upload (sniffLen), and give up with ErrBusy after decodeSlotWait.
//
// decodeCost is based on the peak RSS of one Normalize/NormalizeAvatar of
// 6000x4000 test images, measured in a fresh process built like the release
// (CGO_ENABLED=0, so AVIF runs in WASM; Go 1.27, GOGC=100), in MB per
// megapixel (= bytes per pixel), the larger of Normalize and NormalizeAvatar:
//
//	JPEG baseline 4:2:0 4.5, 4:4:4 5.7, CMYK 14.0
//	JPEG progressive 4:2:0 10.1, 4:4:4 17.4, CMYK 29.3
//	PNG 8-bit RGBA 6.8, 16-bit RGBA 10.6, 16-bit RGBA interlaced 15.4
//	WebP lossy 4.5, lossy + alpha 9.4, lossless 6.8
//	AVIF 8-bit 4:2:0 9.9, 8-bit 4:4:4 + alpha 12.7,
//	     10-bit 4:4:4 30.2, 12-bit 4:4:4 + alpha 32.4
//
// A phone's 12 MP baseline JPEG thus needs ~55 MB and takes one slot; a
// 24 MP progressive 4:4:4 JPEG or a 12 MP 10-bit AVIF takes both slots; a
// high bit depth AVIF over ~18 MP is refused.
const (
	// maxPixels: phones save 12 MP by default (4000x3000), and the app
	// shrinks anything over 1.5 MB to a 2048 px long edge before upload,
	// so 24 MP (6000x4000) leaves plenty of room.
	maxPixels = 24_000_000

	maxConcurrentDecodes = 2
	decodeSlotBytes      = 300 << 20

	// decodeSlotWait is how long an upload waits for its decode slots
	// before it is answered 503 (ErrBusy).
	decodeSlotWait = 20 * time.Second

	// sniffLen is how much of an upload is read before waiting for a slot:
	// enough for the format and the header with the dimensions.
	sniffLen = 256 << 10
)

// ErrBusy: no decode slot became free within decodeSlotWait.
var ErrBusy = errors.New("photos: too many photos are being processed")

var (
	// decodeSlots holds a token for every slot in use.
	decodeSlots = make(chan struct{}, maxConcurrentDecodes)
	// slotQueue lets one acquirer at a time collect its tokens: first come,
	// first served, and two that need both slots never hold one each.
	slotQueue = make(chan struct{}, 1)
	// slotWait is decodeSlotWait; a variable for tests.
	slotWait = decodeSlotWait
	// inSlot, when set (tests), runs right after the slots were taken.
	inSlot func()
)

// acquireDecodeSlots takes n decode slots, waiting at most slotWait and no
// longer than ctx lives (ErrBusy or ctx's error). The returned func gives
// them back.
func acquireDecodeSlots(ctx context.Context, n int) (func(), error) {
	if n < 1 || n > maxConcurrentDecodes {
		return nil, ErrUnsupported
	}
	t := time.NewTimer(slotWait)
	defer t.Stop()
	take := func(c chan struct{}) error {
		select {
		case c <- struct{}{}:
			return nil
		case <-t.C:
			return ErrBusy
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	if err := take(slotQueue); err != nil {
		return nil, err
	}
	defer func() { <-slotQueue }()
	for i := 0; i < n; i++ {
		if err := take(decodeSlots); err != nil {
			for ; i > 0; i-- {
				<-decodeSlots
			}
			return nil, err
		}
	}
	return func() {
		for i := 0; i < n; i++ {
			<-decodeSlots
		}
	}, nil
}

// slotsFor is the number of decode slots an image of format with header
// head (its first bytes) and configuration cfg needs; 0 when it needs more
// than there are.
func slotsFor(format imgFormat, head []byte, cfg image.Config) int {
	cost := decodeCost(format, head, cfg)
	n := (cost + decodeSlotBytes - 1) / decodeSlotBytes
	if n < 1 {
		n = 1
	}
	if n > maxConcurrentDecodes {
		return 0
	}
	return int(n)
}

// decodeCost estimates the peak memory, in bytes, of decoding and
// processing the image (see the measurements above, rounded up).
func decodeCost(format imgFormat, head []byte, cfg image.Config) int64 {
	var bpp float64 // bytes per pixel
	switch format {
	case formatJPEG:
		components, share, progressive, ok := jpegFrame(head)
		switch {
		case !ok:
			bpp = 31 // the worst JPEG
		case components == 4: // CMYK / YCCK
			bpp = 15
		default:
			bpp = 6
		}
		if ok && progressive {
			bpp += 4 * share // one int32 per coefficient, kept until the end
		}
	case formatPNG:
		pix := 4.0 // the decoded image, per pixel
		if len(head) > 24 && head[24] == 16 {
			pix = 8
		}
		bpp = 3 + pix
		if len(head) <= 28 || head[28] != 0 { // interlaced: the passes too
			bpp += pix
		}
	case formatWebP:
		switch cfg.ColorModel {
		case color.YCbCrModel:
			bpp = 5
		case color.NRGBAModel:
			bpp = 7
		default: // lossy with alpha
			bpp = 10
		}
	case formatAVIF:
		bpp = 14
		if cfg.ColorModel == color.RGBA64Model { // more than 8 bits
			bpp = 33
		}
	default:
		bpp = 33
	}
	return int64(bpp * float64(cfg.Width) * float64(cfg.Height))
}

// jpegFrame reads the frame header (SOFn) of a JPEG: the number of
// components, the samples per pixel of all components together (1.5 for
// YCbCr 4:2:0, 3 for 4:4:4) and whether it is progressive.
func jpegFrame(b []byte) (components int, share float64, progressive, ok bool) {
	jpegSegments(b, func(marker byte, seg []byte) bool {
		switch marker {
		case 0xC0, 0xC1, 0xC2:
		case 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF:
			return false // not decodable by image/jpeg anyway
		default:
			return true
		}
		if len(seg) < 6 {
			return false
		}
		n := int(seg[5])
		if n < 1 || len(seg) < 6+3*n {
			return false
		}
		var hmax, vmax, sum int
		for i := 0; i < n; i++ {
			h, v := int(seg[7+3*i]>>4), int(seg[7+3*i]&0xf)
			hmax, vmax, sum = max(hmax, h), max(vmax, v), sum+h*v
		}
		if hmax == 0 || vmax == 0 {
			return false
		}
		components, share, progressive, ok = n, float64(sum)/float64(hmax*vmax), marker == 0xC2, true
		return false
	})
	return
}

// jpegSegments calls fn with every marker segment of a JPEG before the
// image data, until fn returns false.
func jpegSegments(b []byte, fn func(marker byte, seg []byte) bool) {
	if len(b) < 4 || b[0] != 0xFF || b[1] != 0xD8 {
		return
	}
	for i := 2; i+4 <= len(b); {
		if b[i] != 0xFF {
			return
		}
		marker := b[i+1]
		if marker == 0xFF { // fill byte
			i++
			continue
		}
		if marker == 0xDA || marker == 0xD9 { // start of scan, end of image
			return
		}
		size := int(binary.BigEndian.Uint16(b[i+2 : i+4]))
		if size < 2 || i+2+size > len(b) {
			return
		}
		if !fn(marker, b[i+4:i+2+size]) {
			return
		}
		i += 2 + size
	}
}
