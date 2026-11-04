package photos

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/gif"
	"image/jpeg"
	"image/png"
	"io"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gen2brain/avif"
	"golang.org/x/image/bmp"
	"golang.org/x/image/tiff"
)

func testJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 100, 255})
		}
	}
	var b bytes.Buffer
	if err := jpeg.Encode(&b, img, nil); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// resetSlots restores the decode slot settings after a test.
func resetSlots(t *testing.T) {
	t.Cleanup(func() {
		slotWait = decodeSlotWait
		inSlot = nil
		if n := len(decodeSlots); n != 0 {
			t.Errorf("%d decode slots still taken", n)
		}
		if n := len(slotQueue); n != 0 {
			t.Errorf("slot queue still taken")
		}
	})
}

func TestSniffAcceptsOnlyTheFourFormats(t *testing.T) {
	var gifBuf, bmpBuf, tiffBuf bytes.Buffer
	small := image.NewRGBA(image.Rect(0, 0, 4, 4))
	gif.Encode(&gifBuf, small, nil)
	bmp.Encode(&bmpBuf, small)
	tiff.Encode(&tiffBuf, small, nil)
	var pngBuf bytes.Buffer
	png.Encode(&pngBuf, small)
	avifData, err := os.ReadFile("testdata/ispe_lie_16000.avif")
	if err != nil {
		t.Fatal(err)
	}
	heic := append([]byte{0, 0, 0, 24}, []byte("ftypheic\x00\x00\x00\x00mif1heic")...)

	for name, c := range map[string]struct {
		data []byte
		want imgFormat
	}{
		"jpeg": {testJPEG(t, 4, 4), formatJPEG},
		"png":  {pngBuf.Bytes(), formatPNG},
		"webp": {[]byte("RIFF\x00\x00\x00\x00WEBPVP8L\x00\x00\x00\x00"), formatWebP},
		"avif": {avifData, formatAVIF},
		"gif":  {gifBuf.Bytes(), formatUnknown},
		"bmp":  {bmpBuf.Bytes(), formatUnknown},
		"tiff": {tiffBuf.Bytes(), formatUnknown},
		"heic": {heic, formatUnknown},
		"text": {[]byte("hello"), formatUnknown},
	} {
		if got := sniff(c.data); got != c.want {
			t.Errorf("%s: sniff = %d, want %d", name, got, c.want)
		}
		if c.want == formatUnknown {
			if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(c.data), MaxUploadBytes); !errors.Is(err, ErrUnsupported) {
				t.Errorf("%s: Normalize err %v, want ErrUnsupported", name, err)
			}
		}
	}
}

// spyFormat is registered with the image package like imaging registers
// TIFF and BMP. Uploads must never reach any registered decoder by magic
// bytes: image.DecodeConfig did, before the format was checked.
var spyCalls atomic.Int32

func init() {
	image.RegisterFormat("spy", "SPYF", func(io.Reader) (image.Image, error) {
		spyCalls.Add(1)
		return nil, errors.New("spy")
	}, func(io.Reader) (image.Config, error) {
		spyCalls.Add(1)
		return image.Config{Width: 1, Height: 1}, nil
	})
}

func TestUploadsNeverReachRegisteredDecoders(t *testing.T) {
	data := []byte("SPYF and then some bytes")
	if _, _, err := image.DecodeConfig(bytes.NewReader(data)); err != nil || spyCalls.Load() != 1 {
		t.Fatalf("spy not registered: %v %d", err, spyCalls.Load())
	}
	spyCalls.Store(0)
	if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(data), MaxUploadBytes); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("Normalize: %v", err)
	}
	if _, err := NormalizeAvatar(context.Background(), bytes.NewReader(data), MaxUploadBytes); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("NormalizeAvatar: %v", err)
	}
	if n := spyCalls.Load(); n != 0 {
		t.Fatalf("a registered decoder was called %d times", n)
	}
}

// pngClaiming is a 1x1 PNG whose header claims w x h (valid CRC).
func pngClaiming(t *testing.T, w, h uint32) []byte {
	t.Helper()
	var b bytes.Buffer
	png.Encode(&b, image.NewGray(image.Rect(0, 0, 1, 1)))
	d := b.Bytes()
	binary.BigEndian.PutUint32(d[16:20], w)
	binary.BigEndian.PutUint32(d[20:24], h)
	binary.BigEndian.PutUint32(d[29:33], crc32.ChecksumIEEE(d[12:29]))
	return d
}

func TestPixelLimitBeforeDecoding(t *testing.T) {
	resetSlots(t)
	decoded := false
	inSlot = func() { decoded = true }
	big := pngClaiming(t, 6000, 4001) // just over 24 MP
	if _, err := png.DecodeConfig(bytes.NewReader(big)); err != nil {
		t.Fatalf("fixture: %v", err)
	}
	if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(big), MaxUploadBytes); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("Normalize: %v", err)
	}
	if decoded {
		t.Fatal("an image over the pixel limit got a decode slot")
	}
}

// The AVIF decoder sizes its buffers by the AV1 frame, not by the ispe box
// that avif.DecodeConfig reports. The fixture is a 3 KB 16000x16000 AVIF
// (avifenc) whose ispe was patched to 100x100: undetected, its decode took
// ~360 MB.
func TestAVIFWithALyingHeaderIsRefused(t *testing.T) {
	resetSlots(t)
	data, err := os.ReadFile("testdata/ispe_lie_16000.avif")
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := avif.DecodeConfig(bytes.NewReader(data))
	if err != nil || cfg.Width != 100 || cfg.Height != 100 {
		t.Fatalf("fixture: %+v %v", cfg, err)
	}
	if err := checkAVIF(data); err == nil {
		t.Fatal("checkAVIF accepted a 16000x16000 frame")
	}
	start := time.Now()
	if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(data), MaxUploadBytes); !errors.Is(err, ErrUnsupported) {
		t.Fatalf("Normalize: %v", err)
	}
	if d := time.Since(start); d > 2*time.Second {
		t.Fatalf("took %v: was it decoded?", d)
	}
}

func TestAVIFCheckReadsTheSequenceHeader(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 96, 40))
	var b bytes.Buffer
	if err := avif.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	if err := checkAVIF(b.Bytes()); err != nil {
		t.Fatalf("checkAVIF on a plain AVIF: %v", err)
	}
	// its AV1 items (colour, and alpha: the image is transparent)
	types, _ := func() (map[uint32]string, error) {
		var meta []byte
		eachBox(b.Bytes(), func(typ string, p []byte) error {
			if typ == "meta" {
				meta = p[4:]
			}
			return nil
		})
		var iinf []byte
		eachBox(meta, func(typ string, p []byte) error {
			if typ == "iinf" {
				iinf = p
			}
			return nil
		})
		return itemTypes(iinf)
	}()
	n := 0
	for _, typ := range types {
		if typ == "av01" {
			n++
		}
	}
	if n != 2 {
		t.Fatalf("items %v", types)
	}
	// truncated or garbage files are refused
	for _, bad := range [][]byte{b.Bytes()[:len(b.Bytes())/2], b.Bytes()[:40], []byte("\x00\x00\x00\x10ftypavif\x00\x00\x00\x00")} {
		if checkAVIF(bad) == nil {
			t.Fatalf("checkAVIF accepted %d bytes of garbage", len(bad))
		}
	}
}

func TestSeqHeaderMaxFrame(t *testing.T) {
	// reduced_still_picture_header: profile 0, still 1, reduced 1, level 0,
	// 16 bit widths, 16000x9000 -> 15999, 8999
	var bits []byte
	put := func(v uint64, n int) {
		for i := n - 1; i >= 0; i-- {
			bits = append(bits, byte(v>>i&1))
		}
	}
	put(0, 3)
	put(1, 1)
	put(1, 1)
	put(0, 5)
	put(15, 4)
	put(15, 4)
	put(15999, 16)
	put(8999, 16)
	b := make([]byte, (len(bits)+7)/8)
	for i, v := range bits {
		b[i/8] |= v << (7 - i%8)
	}
	w, h, ok := seqHeaderMaxFrame(b)
	if !ok || w != 16000 || h != 9000 {
		t.Fatalf("got %dx%d ok=%v", w, h, ok)
	}
	if _, _, ok := seqHeaderMaxFrame(b[:3]); ok {
		t.Fatal("truncated header accepted")
	}
}

func TestJPEGOrientationIsApplied(t *testing.T) {
	// left half red, right half blue, 80x40, EXIF orientation 6 (the
	// camera was turned clockwise): shown 40x80 with red on top
	img := image.NewRGBA(image.Rect(0, 0, 80, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 80; x++ {
			c := color.RGBA{220, 0, 0, 255}
			if x >= 40 {
				c = color.RGBA{0, 0, 220, 255}
			}
			img.Set(x, y, c)
		}
	}
	var b bytes.Buffer
	jpeg.Encode(&b, img, &jpeg.Options{Quality: 95})
	tiffBlock := []byte("MM\x00\x2a\x00\x00\x00\x08" + // header, IFD0 at 8
		"\x00\x01" + // one entry
		"\x01\x12\x00\x03\x00\x00\x00\x01\x00\x06\x00\x00" + // Orientation SHORT 6
		"\x00\x00\x00\x00")
	payload := append([]byte("Exif\x00\x00"), tiffBlock...)
	seg := []byte{0xFF, 0xE1, byte((len(payload) + 2) >> 8), byte(len(payload) + 2)}
	src := append(append(append([]byte{}, b.Bytes()[:2]...), append(seg, payload...)...), b.Bytes()[2:]...)
	if o := jpegOrientation(src); o != 6 {
		t.Fatalf("orientation %d", o)
	}

	full, _, w, h, err := Normalize(context.Background(), bytes.NewReader(src), MaxUploadBytes)
	if err != nil || w != 40 || h != 80 {
		t.Fatalf("Normalize: %dx%d %v", w, h, err)
	}
	out, _ := jpeg.Decode(bytes.NewReader(full))
	r, _, bl, _ := out.At(20, 10).RGBA()
	if r>>8 < 150 || bl>>8 > 80 {
		t.Fatalf("top is not red: r=%d b=%d", r>>8, bl>>8)
	}
	r, _, bl, _ = out.At(20, 70).RGBA()
	if bl>>8 < 150 || r>>8 > 80 {
		t.Fatalf("bottom is not blue: r=%d b=%d", r>>8, bl>>8)
	}
}

// At most maxConcurrentDecodes images are decoded at once, whatever the
// number of uploads.
func TestParallelDecodesAreCapped(t *testing.T) {
	resetSlots(t)
	var active, peak atomic.Int32
	inSlot = func() {
		n := active.Add(1)
		for {
			p := peak.Load()
			if n <= p || peak.CompareAndSwap(p, n) {
				break
			}
		}
		time.Sleep(30 * time.Millisecond)
		active.Add(-1)
	}
	data := testJPEG(t, 64, 48)
	var wg sync.WaitGroup
	errs := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(avatar bool) {
			defer wg.Done()
			var err error
			if avatar {
				_, err = NormalizeAvatar(context.Background(), bytes.NewReader(data), MaxUploadBytes)
			} else {
				_, _, _, _, err = Normalize(context.Background(), bytes.NewReader(data), MaxUploadBytes)
			}
			errs <- err
		}(i%2 == 0)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if p := peak.Load(); p != maxConcurrentDecodes {
		t.Fatalf("peak parallel decodes %d, want %d", p, maxConcurrentDecodes)
	}
}

func TestBusyWhenNoSlotFreesUp(t *testing.T) {
	resetSlots(t)
	slotWait = 50 * time.Millisecond
	release, err := acquireDecodeSlots(context.Background(), maxConcurrentDecodes)
	if err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	_, _, _, _, err = Normalize(context.Background(), bytes.NewReader(testJPEG(t, 8, 8)), MaxUploadBytes)
	if !errors.Is(err, ErrBusy) || time.Since(start) < slotWait {
		t.Fatalf("err %v after %v", err, time.Since(start))
	}
	release()
	if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(testJPEG(t, 8, 8)), MaxUploadBytes); err != nil {
		t.Fatalf("after release: %v", err)
	}
}

func TestWaitingForASlotEndsWithTheRequest(t *testing.T) {
	resetSlots(t)
	slotWait = time.Minute
	release, err := acquireDecodeSlots(context.Background(), maxConcurrentDecodes)
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(30*time.Millisecond, cancel)
	start := time.Now()
	_, err = NormalizeAvatar(ctx, bytes.NewReader(testJPEG(t, 8, 8)), MaxUploadBytes)
	if !errors.Is(err, context.Canceled) || time.Since(start) > 5*time.Second {
		t.Fatalf("err %v after %v", err, time.Since(start))
	}
}

// An image that needs both slots waits until both are free and then runs
// alone; it never holds one slot while another such image holds the other.
func TestHeavyImageTakesBothSlots(t *testing.T) {
	resetSlots(t)
	slotWait = 50 * time.Millisecond
	one, err := acquireDecodeSlots(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := acquireDecodeSlots(context.Background(), 2); !errors.Is(err, ErrBusy) {
		t.Fatalf("two slots while one is taken: %v", err)
	}
	if len(decodeSlots) != 1 {
		t.Fatalf("a failed acquire kept slots: %d", len(decodeSlots))
	}
	one()
	slotWait = 5 * time.Second
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			release, err := acquireDecodeSlots(context.Background(), 2)
			if err != nil {
				t.Error(err)
				return
			}
			if n := len(decodeSlots); n != 2 {
				t.Errorf("%d slots taken", n)
			}
			time.Sleep(5 * time.Millisecond)
			release()
		}()
	}
	wg.Wait()
}

// sof is a JPEG with just a frame header: SOI, SOFn, EOI.
func sof(marker byte, w, h int, sampling ...byte) []byte {
	seg := []byte{8, byte(h >> 8), byte(h), byte(w >> 8), byte(w), byte(len(sampling))}
	for i, s := range sampling {
		seg = append(seg, byte(i+1), s, 0)
	}
	out := []byte{0xFF, 0xD8, 0xFF, marker, byte((len(seg) + 2) >> 8), byte(len(seg) + 2)}
	return append(append(out, seg...), 0xFF, 0xD9)
}

func TestSlotsFor(t *testing.T) {
	pngHead := func(depth, interlace byte) []byte {
		h := make([]byte, 33)
		h[24], h[28] = depth, interlace
		return h
	}
	cfg := func(w, h int, m color.Model) image.Config { return image.Config{ColorModel: m, Width: w, Height: h} }
	for _, c := range []struct {
		name   string
		format imgFormat
		head   []byte
		cfg    image.Config
		want   int
	}{
		{"12 MP phone JPEG", formatJPEG, sof(0xC0, 4000, 3000, 0x22, 0x11, 0x11), cfg(4000, 3000, color.YCbCrModel), 1},
		{"24 MP baseline 4:4:4", formatJPEG, sof(0xC0, 6000, 4000, 0x11, 0x11, 0x11), cfg(6000, 4000, color.YCbCrModel), 1},
		{"24 MP progressive 4:2:0", formatJPEG, sof(0xC2, 6000, 4000, 0x22, 0x11, 0x11), cfg(6000, 4000, color.YCbCrModel), 1},
		{"24 MP progressive 4:4:4", formatJPEG, sof(0xC2, 6000, 4000, 0x11, 0x11, 0x11), cfg(6000, 4000, color.YCbCrModel), 2},
		{"24 MP progressive CMYK", formatJPEG, sof(0xC2, 6000, 4000, 0x11, 0x11, 0x11, 0x11), cfg(6000, 4000, color.CMYKModel), 0},
		{"JPEG without frame header", formatJPEG, []byte{0xFF, 0xD8, 0xFF}, cfg(4000, 3000, color.YCbCrModel), 2},
		{"24 MP PNG 16 bit", formatPNG, pngHead(16, 0), cfg(6000, 4000, color.NRGBA64Model), 1},
		{"24 MP PNG 16 bit interlaced", formatPNG, pngHead(16, 1), cfg(6000, 4000, color.NRGBA64Model), 2},
		{"24 MP WebP lossy", formatWebP, nil, cfg(6000, 4000, color.YCbCrModel), 1},
		{"12 MP AVIF 8 bit", formatAVIF, nil, cfg(4000, 3000, color.RGBAModel), 1},
		{"24 MP AVIF 8 bit", formatAVIF, nil, cfg(6000, 4000, color.RGBAModel), 2},
		{"12 MP AVIF 10 bit", formatAVIF, nil, cfg(4000, 3000, color.RGBA64Model), 2},
		{"24 MP AVIF 10 bit", formatAVIF, nil, cfg(6000, 4000, color.RGBA64Model), 0},
	} {
		if got := slotsFor(c.format, c.head, c.cfg); got != c.want {
			t.Errorf("%s: %d slots, want %d (cost %d MB)", c.name, got, c.want, decodeCost(c.format, c.head, c.cfg)>>20)
		}
	}
}

func TestOversizedUploadIsTooLarge(t *testing.T) {
	resetSlots(t)
	big := append(testJPEG(t, 10, 10), make([]byte, MaxUploadBytes)...)
	if _, _, _, _, err := Normalize(context.Background(), bytes.NewReader(big), MaxUploadBytes); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err %v", err)
	}
}
