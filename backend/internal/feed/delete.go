package feed

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

// ErrUpdateNotFound is returned by DeleteUpdateByID for an unknown update.
var ErrUpdateNotFound = errNotFound

// DeleteUpdateByID deletes any update (active or hidden) with its photo rows,
// photo files (best-effort) and reports, for moderation. The author-only
// checks stay in the public route.
func DeleteUpdateByID(ctx context.Context, db *sql.DB, uploadDir string, id uint64) error {
	return removeUpdate(ctx, db, uploadDir, id, nil)
}

// ErrInvalidStatus: an update status other than active or hidden.
var ErrInvalidStatus = errors.New("feed: invalid status")

// AdminEditUpdate changes any update, whoever wrote it and whatever its
// spot's lock (nil = unchanged): text, tag and status (active / hidden).
// The text rules are the author's: at most MaxBodyLen, and text or photos.
func AdminEditUpdate(ctx context.Context, db *sql.DB, id uint64, body, tag, status *string) error {
	if tag != nil && !ValidTag(*tag) {
		return ErrInvalidTag
	}
	if status != nil && *status != "active" && *status != "hidden" {
		return ErrInvalidStatus
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var cur string
	err = tx.QueryRowContext(ctx, "SELECT body FROM spot_updates WHERE id = ? FOR UPDATE", id).Scan(&cur)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrUpdateNotFound
	}
	if err != nil {
		return err
	}
	newBody := cur
	if body != nil {
		newBody = strings.TrimSpace(*body)
	}
	var photos int
	if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM photos WHERE update_id = ?", id).Scan(&photos); err != nil {
		return err
	}
	if len(newBody) > MaxBodyLen || (newBody == "" && photos == 0) {
		return ErrInvalidBody
	}
	// Only a text or tag change counts as "edited"; hiding does not.
	edited := (body != nil && newBody != cur) || tag != nil
	if _, err := tx.ExecContext(ctx, `UPDATE spot_updates SET body = ?, tag = COALESCE(?, tag),
			status = COALESCE(?, status),
			edited_at = IF(?, CURRENT_TIMESTAMP, edited_at)
		WHERE id = ?`, newBody, tag, status, edited, id); err != nil {
		return err
	}
	return tx.Commit()
}
