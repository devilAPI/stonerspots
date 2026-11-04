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

// CleanupUnattached deletes photo files and rows that were never attached to
// an update (update_id NULL) and are older than maxAge. Returns number of
// deleted rows. It only looks at the photos table and deletes only the keys
// stored there; it never lists the upload dir, so files that are not photos
// (avatars, see avatar.go) are never touched.
func CleanupUnattached(ctx context.Context, db *sql.DB, storage Storage, maxAge time.Duration) (int, error) {
	cutoff := time.Now().UTC().Add(-maxAge)
	rows, err := db.QueryContext(ctx,
		"SELECT id, `key`, thumb_key FROM photos WHERE update_id IS NULL AND created_at < ?", cutoff)
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
		// still unattached: it may have been attached since the SELECT
		res, err := db.ExecContext(ctx, `DELETE FROM photos WHERE id = ? AND update_id IS NULL`, id)
		if err != nil {
			log.Printf("photos: cleanup delete row %d: %v", id, err)
			continue
		}
		if n, _ := res.RowsAffected(); n != 1 {
			continue
		}
		keys = append(keys, key, thumbKey)
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
	run := func() {
		if _, err := CleanupUnattached(ctx, db, storage, maxAge); err != nil && ctx.Err() == nil {
			log.Printf("photos: cleanup: %v", err)
		}
	}
	run() // once at start
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			run()
		}
	}
}
