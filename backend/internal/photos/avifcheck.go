package photos

import (
	"encoding/binary"
	"errors"
)

// The AVIF decoder (libavif + dav1d in WASM) allocates by the size in the
// AV1 bitstream, not by the "ispe" box that avif.DecodeConfig reports, and
// it accepts frames up to 16384x16384. A 3 KB file that claims 100x100 in
// ispe but carries a 16000x16000 frame made one decode take ~360 MB, and
// past maxPixels. checkAVIF therefore reads the frame size limit from the
// AV1 sequence header of every AV1 item, the way the decoder will see it,
// and refuses files it cannot account for (fail closed).

var errAVIF = errors.New("photos: avif layout not accepted")

const (
	maxAVIFItems = 256 // AV1 items (tiles, alpha, gain map) in one file
	maxAVIFBoxes = 4096
)

// checkAVIF returns nil when every AV1 item of data has a sequence header
// whose maximum frame size is within maxPixels, all of them together
// within 2*maxPixels (colour + alpha), and every grid's output within
// maxPixels. Image sequences (a moov box) are refused.
func checkAVIF(data []byte) error {
	var meta []byte
	nMeta := 0
	if err := eachBox(data, func(typ string, p []byte) error {
		switch typ {
		case "moov": // image sequence: decoded from tracks, not items
			return errAVIF
		case "meta":
			nMeta++
			meta = p
		}
		return nil
	}); err != nil || nMeta != 1 || len(meta) < 4 {
		return errAVIF
	}
	meta = meta[4:] // FullBox version and flags

	var iinf, iloc, idat []byte
	if err := eachBox(meta, func(typ string, p []byte) error {
		var dst *[]byte
		switch typ {
		case "iinf":
			dst = &iinf
		case "iloc":
			dst = &iloc
		case "idat":
			dst = &idat
		default:
			return nil
		}
		if *dst != nil {
			return errAVIF // duplicate box
		}
		*dst = p
		return nil
	}); err != nil || iinf == nil || iloc == nil {
		return errAVIF
	}

	types, err := itemTypes(iinf)
	if err != nil {
		return err
	}
	locs, err := itemLocations(iloc)
	if err != nil {
		return err
	}

	var items int
	var total int64
	for id, typ := range types {
		if typ != "av01" && typ != "grid" {
			continue
		}
		payload, err := locs.payload(id, data, idat)
		if err != nil {
			return err
		}
		if typ == "grid" {
			w, h, err := gridOutput(payload)
			if err != nil || w*h > maxPixels {
				return errAVIF
			}
			continue
		}
		items++
		if items > maxAVIFItems {
			return errAVIF
		}
		w, h, err := av1MaxFrame(payload)
		if err != nil || w*h > maxPixels {
			return errAVIF
		}
		total += w * h
		if total > 2*maxPixels {
			return errAVIF
		}
	}
	if items == 0 {
		return errAVIF
	}
	return nil
}

// eachBox calls fn for every box in b, in order. A box that does not fit,
// or too many boxes, is an error.
func eachBox(b []byte, fn func(typ string, payload []byte) error) error {
	for n := 0; len(b) > 0; n++ {
		if n >= maxAVIFBoxes || len(b) < 8 {
			return errAVIF
		}
		size := uint64(binary.BigEndian.Uint32(b[:4]))
		typ := string(b[4:8])
		hdr := uint64(8)
		switch size {
		case 0: // to the end
			size = uint64(len(b))
		case 1:
			if len(b) < 16 {
				return errAVIF
			}
			size, hdr = binary.BigEndian.Uint64(b[8:16]), 16
		}
		if size < hdr || size > uint64(len(b)) {
			return errAVIF
		}
		if err := fn(typ, b[hdr:size]); err != nil {
			return err
		}
		b = b[size:]
	}
	return nil
}

// itemTypes reads the item ids and their types from an iinf payload.
func itemTypes(p []byte) (map[uint32]string, error) {
	if len(p) < 6 {
		return nil, errAVIF
	}
	off := 6 // version, flags, entry_count (16 bit)
	if p[0] != 0 {
		off = 8 // 32 bit entry_count
	}
	if len(p) < off {
		return nil, errAVIF
	}
	types := map[uint32]string{}
	err := eachBox(p[off:], func(typ string, e []byte) error {
		if typ != "infe" || len(e) < 4 {
			return errAVIF
		}
		var id uint32
		var rest []byte
		switch e[0] { // older infe versions carry no item type
		case 2:
			if len(e) < 12 {
				return errAVIF
			}
			id, rest = uint32(binary.BigEndian.Uint16(e[4:6])), e[6:]
		case 3:
			if len(e) < 14 {
				return errAVIF
			}
			id, rest = binary.BigEndian.Uint32(e[4:8]), e[8:]
		default:
			return errAVIF
		}
		if _, dup := types[id]; dup {
			return errAVIF
		}
		types[id] = string(rest[2:6]) // after item_protection_index
		return nil
	})
	return types, err
}

type extent struct{ off, len uint64 }

type itemLoc struct {
	method  uint16 // 0 file offset, 1 idat offset
	base    uint64
	extents []extent
}

type locations map[uint32]itemLoc

// itemLocations parses an iloc payload.
func itemLocations(p []byte) (locations, error) {
	if len(p) < 8 {
		return nil, errAVIF
	}
	version := p[0]
	if version > 2 {
		return nil, errAVIF
	}
	offSize, lenSize := int(p[4]>>4), int(p[4]&0xf)
	baseSize, idxSize := int(p[5]>>4), int(p[5]&0xf)
	if version == 0 {
		idxSize = 0
	}
	off := 6
	r := func(n int) (uint64, bool) {
		if n != 0 && n != 2 && n != 4 && n != 8 {
			return 0, false
		}
		if off+n > len(p) {
			return 0, false
		}
		var v uint64
		for i := 0; i < n; i++ {
			v = v<<8 | uint64(p[off+i])
		}
		off += n
		return v, true
	}
	countSize := 2
	if version == 2 {
		countSize = 4
	}
	count, ok := r(countSize)
	if !ok {
		return nil, errAVIF
	}
	locs := locations{}
	for i := uint64(0); i < count; i++ {
		idSize := 2
		if version == 2 {
			idSize = 4
		}
		id, ok := r(idSize)
		if !ok {
			return nil, errAVIF
		}
		var loc itemLoc
		if version >= 1 {
			m, ok := r(2)
			if !ok {
				return nil, errAVIF
			}
			loc.method = uint16(m & 0xf)
		}
		if _, ok := r(2); !ok { // data_reference_index
			return nil, errAVIF
		}
		if loc.base, ok = r(baseSize); !ok {
			return nil, errAVIF
		}
		n, ok := r(2)
		if !ok || n == 0 {
			return nil, errAVIF
		}
		for e := uint64(0); e < n; e++ {
			if _, ok := r(idxSize); !ok {
				return nil, errAVIF
			}
			o, ok1 := r(offSize)
			l, ok2 := r(lenSize)
			if !ok1 || !ok2 {
				return nil, errAVIF
			}
			loc.extents = append(loc.extents, extent{o, l})
		}
		if _, dup := locs[uint32(id)]; dup {
			return nil, errAVIF
		}
		locs[uint32(id)] = loc
	}
	return locs, nil
}

// payload is the data of item id: its extents, concatenated, from the file
// (construction method 0) or the idat box (1).
func (l locations) payload(id uint32, file, idat []byte) ([]byte, error) {
	loc, ok := l[id]
	if !ok {
		return nil, errAVIF
	}
	var src []byte
	switch loc.method {
	case 0:
		src = file
	case 1:
		src = idat
	default:
		return nil, errAVIF
	}
	var out []byte
	for _, e := range loc.extents {
		start := loc.base + e.off
		if start < loc.base || start > uint64(len(src)) {
			return nil, errAVIF
		}
		end := uint64(len(src))
		if e.len != 0 {
			end = start + e.len
			if end < start || end > uint64(len(src)) {
				return nil, errAVIF
			}
		}
		if len(loc.extents) == 1 {
			return src[start:end], nil
		}
		if uint64(len(out))+(end-start) > uint64(len(file)) {
			return nil, errAVIF
		}
		out = append(out, src[start:end]...)
	}
	return out, nil
}

// gridOutput reads the output size of an ImageGrid item.
func gridOutput(p []byte) (w, h int64, err error) {
	if len(p) < 8 || p[0] != 0 {
		return 0, 0, errAVIF
	}
	if p[1]&1 == 0 {
		return int64(binary.BigEndian.Uint16(p[4:6])), int64(binary.BigEndian.Uint16(p[6:8])), nil
	}
	if len(p) < 12 {
		return 0, 0, errAVIF
	}
	return int64(binary.BigEndian.Uint32(p[4:8])), int64(binary.BigEndian.Uint32(p[8:12])), nil
}

// av1MaxFrame walks the OBUs of an AV1 item and returns the largest
// max_frame_width x max_frame_height among its sequence headers. dav1d
// refuses frames larger than their sequence header allows. An item without
// a sequence header is an error.
func av1MaxFrame(d []byte) (w, h int64, err error) {
	found := false
	for len(d) > 0 {
		hdr := d[0]
		if hdr&0x80 != 0 {
			return 0, 0, errAVIF // forbidden bit
		}
		typ := hdr >> 3 & 0xf
		n := 1
		if hdr&0x04 != 0 { // extension header
			n++
		}
		if len(d) < n {
			return 0, 0, errAVIF
		}
		size := uint64(len(d) - n)
		if hdr&0x02 != 0 { // has size field
			var k int
			size, k = leb128(d[n:])
			if k == 0 {
				return 0, 0, errAVIF
			}
			n += k
		}
		if size > uint64(len(d)-n) {
			return 0, 0, errAVIF
		}
		obu := d[n : n+int(size)]
		d = d[n+int(size):]
		if typ != 1 { // OBU_SEQUENCE_HEADER
			continue
		}
		sw, sh, ok := seqHeaderMaxFrame(obu)
		if !ok {
			return 0, 0, errAVIF
		}
		found = true
		if sw*sh > w*h {
			w, h = sw, sh
		}
	}
	if !found {
		return 0, 0, errAVIF
	}
	return w, h, nil
}

func leb128(b []byte) (uint64, int) {
	var v uint64
	for i := 0; i < 8 && i < len(b); i++ {
		v |= uint64(b[i]&0x7f) << (7 * i)
		if b[i]&0x80 == 0 {
			return v, i + 1
		}
	}
	return 0, 0
}

type bitReader struct {
	b   []byte
	pos int // in bits
	bad bool
}

func (r *bitReader) f(n int) uint64 {
	var v uint64
	for i := 0; i < n; i++ {
		if r.pos>>3 >= len(r.b) {
			r.bad = true
			return 0
		}
		v = v<<1 | uint64(r.b[r.pos>>3]>>(7-r.pos&7)&1)
		r.pos++
	}
	return v
}

func (r *bitReader) uvlc() {
	zeros := 0
	for r.f(1) == 0 {
		if r.bad || zeros >= 32 {
			r.bad = true
			return
		}
		zeros++
	}
	r.f(zeros)
}

// seqHeaderMaxFrame parses an AV1 sequence_header_obu (AV1 spec 5.5.1) up
// to max_frame_width_minus_1 / max_frame_height_minus_1.
func seqHeaderMaxFrame(b []byte) (w, h int64, ok bool) {
	r := &bitReader{b: b}
	r.f(3)           // seq_profile
	r.f(1)           // still_picture
	if r.f(1) == 1 { // reduced_still_picture_header
		r.f(5) // seq_level_idx[0]
	} else {
		decoderModelInfo := false
		bufferDelayLen := 0
		if r.f(1) == 1 { // timing_info_present_flag
			r.f(32)          // num_units_in_display_tick
			r.f(32)          // time_scale
			if r.f(1) == 1 { // equal_picture_interval
				r.uvlc() // num_ticks_per_picture_minus_1
			}
			if r.f(1) == 1 { // decoder_model_info_present_flag
				decoderModelInfo = true
				bufferDelayLen = int(r.f(5)) + 1
				r.f(32) // num_units_in_decoding_tick
				r.f(5)  // buffer_removal_time_length_minus_1
				r.f(5)  // frame_presentation_time_length_minus_1
			}
		}
		initialDisplayDelay := r.f(1) == 1
		ops := int(r.f(5)) + 1
		for i := 0; i < ops && !r.bad; i++ {
			r.f(12)         // operating_point_idc
			if r.f(5) > 7 { // seq_level_idx
				r.f(1) // seq_tier
			}
			if decoderModelInfo && r.f(1) == 1 {
				r.f(bufferDelayLen) // decoder_buffer_delay
				r.f(bufferDelayLen) // encoder_buffer_delay
				r.f(1)              // low_delay_mode_flag
			}
			if initialDisplayDelay && r.f(1) == 1 {
				r.f(4) // initial_display_delay_minus_1
			}
		}
	}
	wBits := int(r.f(4)) + 1
	hBits := int(r.f(4)) + 1
	w = int64(r.f(wBits)) + 1
	h = int64(r.f(hBits)) + 1
	return w, h, !r.bad
}
