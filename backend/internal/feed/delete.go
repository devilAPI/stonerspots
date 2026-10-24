package feed

import (
	"context"
	"database/sql"
)

// ErrUpdateNotFound is returned by DeleteUpdateByID for an unknown update.
var ErrUpdateNotFound = errNotFound

// DeleteUpdateByID deletes any update (active or hidden) with its photo rows,
// photo files (best-effort) and reports, for moderation. The author-only
// checks stay in the public route.
func DeleteUpdateByID(ctx context.Context, db *sql.DB, uploadDir string, id uint64) error {
	return removeUpdate(ctx, db, uploadDir, id, nil)
}
