package zones

import (
	"bytes"
	"compress/gzip"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"time"
)

// maxBlob guards against a corrupt row unpacking into something huge
// (a dense city tile is a few hundred kB of JSON).
const maxBlob = 32 << 20

// dbStore keeps tiles in the zone_tiles table (migration 0028) as gzipped
// JSON.
type dbStore struct{ db *sql.DB }

func (s dbStore) load(ctx context.Context, key string) (tileData, bool, error) {
	var blob []byte
	var fetched time.Time
	err := s.db.QueryRowContext(ctx,
		`SELECT data, fetched_at FROM zone_tiles WHERE tile_key = ?`, key).Scan(&blob, &fetched)
	if errors.Is(err, sql.ErrNoRows) {
		return tileData{}, false, nil
	}
	if err != nil {
		return tileData{}, false, err
	}
	zr, err := gzip.NewReader(bytes.NewReader(blob))
	if err != nil {
		return tileData{}, false, err
	}
	var d tileData
	if err := json.NewDecoder(io.LimitReader(zr, maxBlob)).Decode(&d); err != nil {
		return tileData{}, false, err
	}
	d.FetchedAt = fetched
	return d, true, nil
}

func (s dbStore) save(ctx context.Context, key string, d tileData) error {
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if err := json.NewEncoder(zw).Encode(d); err != nil {
		return err
	}
	if err := zw.Close(); err != nil {
		return err
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO zone_tiles (tile_key, data, fetched_at) VALUES (?, ?, ?)
		ON DUPLICATE KEY UPDATE data = VALUES(data), fetched_at = VALUES(fetched_at)`,
		key, buf.Bytes(), d.FetchedAt.UTC())
	return err
}
