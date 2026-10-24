package feed

import (
	"encoding/base64"
	"encoding/json"
	"errors"
)

// ErrInvalidCursor is returned by DecodeCursor for malformed cursors.
var ErrInvalidCursor = errors.New("feed: invalid cursor")

type cursorPayload struct {
	K  float64 `json:"k"`
	ID uint64  `json:"id"`
}

// EncodeCursor builds an opaque base64 JSON cursor from the sort key and row id.
func EncodeCursor(sortKey float64, id uint64) string {
	b, _ := json.Marshal(cursorPayload{K: sortKey, ID: id})
	return base64.RawURLEncoding.EncodeToString(b)
}

// DecodeCursor parses a cursor produced by EncodeCursor.
func DecodeCursor(s string) (sortKey float64, id uint64, err error) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, 0, ErrInvalidCursor
	}
	var p struct {
		K  *float64 `json:"k"`
		ID *uint64  `json:"id"`
	}
	if err := json.Unmarshal(b, &p); err != nil || p.K == nil || p.ID == nil {
		return 0, 0, ErrInvalidCursor
	}
	return *p.K, *p.ID, nil
}
