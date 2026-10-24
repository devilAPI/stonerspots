package reviews

import (
	"context"
	"database/sql"
	"errors"
)

// ErrNotFound is returned by DeleteByID for an unknown review.
var ErrNotFound = errors.New("reviews: review not found")

// deleteInTx removes a review and all reports about it (reports are
// polymorphic, no FK).
func deleteInTx(ctx context.Context, tx *sql.Tx, id uint64) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM reports WHERE target_type = 'review' AND target_id = ?`, id); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `DELETE FROM spot_reviews WHERE id = ?`, id)
	return err
}

// DeleteByID deletes any review (active or hidden) with its reports, for
// moderation. The author-only checks live in the public route.
func DeleteByID(ctx context.Context, db *sql.DB, id uint64) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var one uint64
	err = tx.QueryRowContext(ctx, `SELECT id FROM spot_reviews WHERE id = ? FOR UPDATE`, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if err := deleteInTx(ctx, tx, id); err != nil {
		return err
	}
	return tx.Commit()
}
