// Package photos: periodic cleanup of unattached photos older than 24h.
package photos

import (
	"context"
	"database/sql"
	"log"
	"path/filepath"
	"strings"
	"time"
)

// CleanupUnattached deletes photo files and rows that are not referenced by
// any spot or update and are older than maxAge. Returns number of deleted rows.
func CleanupUnattached(ctx context.Context, db *sql.DB, storage Storage, maxAge time.Duration) (int, error) {
	cutoff := time.Now().UTC().Add(-maxAge)
	rows, err := db.QueryContext(ctx,
		"SELECT id, `key`, thumb_key FROM photos "+
			"WHERE created_at < ? AND id NOT IN ("+
			"  SELECT photo_id FROM spot_updates WHERE photo_id IS NOT NULL"+
			") AND id NOT IN ("+
			"  SELECT photo_id FROM spots WHERE photo_id IS NOT NULL"+
			")", cutoff)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	var deleted int
	var keys []string
	for rows.Next() {
		var id int64
		var key, thumbKey string
		if err := rows.Scan(&id, &key, &thumbKey); err != nil {
			return deleted, err
		}
		keys = append(keys, key, thumbKey)
		_, err := db.ExecContext(ctx, `DELETE FROM photos WHERE id = ?`, id)
		if err != nil {
			log.Printf("photos: cleanup delete row %d: %v", id, err)
			continue
		}
		deleted++
	}
	if err := rows.Err(); err != nil {
		return deleted, err
	}

	// Delete files from storage
	for _, k := range keys {
		if k == "" || strings.Contains(k, "..") || strings.HasPrefix(k, "/") || filepath.IsAbs(k) {
			continue
		}
		if err := storage.Delete(ctx, k); err != nil {
			log.Printf("photos: cleanup delete file %q: %v", k, err)
		}
	}

	if deleted > 0 {
		log.Printf("photos: cleanup deleted %d unattached photos older than %v", deleted, maxAge)
	}
	return deleted, nil
}

// StartCleanupJob runs CleanupUnattached every interval until ctx is cancelled.
func StartCleanupJob(ctx context.Context, db *sql.DB, storage Storage, maxAge, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	// Run once at start
	CleanupUnattached(ctx, db, storage, maxAge)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			CleanupUnattached(ctx, db, storage, maxAge)
		}
	}
}