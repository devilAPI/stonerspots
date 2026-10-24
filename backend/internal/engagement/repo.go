package engagement

import (
	"context"
	"database/sql"
	"errors"
)

var (
	errNotFound = errors.New("not found")
	errBadType  = errors.New("invalid target type")
)

const hideThreshold = 3

type repo struct{ db *sql.DB }

func (r repo) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// lockSpot locks the spot row (serialising concurrent like changes) and
// returns errNotFound if it does not exist.
func lockSpot(ctx context.Context, tx *sql.Tx, id uint64) error {
	var x uint64
	err := tx.QueryRowContext(ctx, `SELECT id FROM spots WHERE id = ? FOR UPDATE`, id).Scan(&x)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	return err
}

// SetLike adds or removes the like and keeps spots.like_count equal to the
// number of spot_likes rows. It returns the resulting count.
func (r repo) SetLike(ctx context.Context, userID, spotID uint64, liked bool) (int, error) {
	var count int
	err := r.inTx(ctx, func(tx *sql.Tx) error {
		if err := lockSpot(ctx, tx, spotID); err != nil {
			return err
		}
		var res sql.Result
		var err error
		if liked {
			res, err = tx.ExecContext(ctx, `INSERT IGNORE INTO spot_likes (user_id, spot_id) VALUES (?, ?)`, userID, spotID)
		} else {
			res, err = tx.ExecContext(ctx, `DELETE FROM spot_likes WHERE user_id = ? AND spot_id = ?`, userID, spotID)
		}
		if err != nil {
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n > 0 {
			delta := 1
			if !liked {
				delta = -1
			}
			if _, err := tx.ExecContext(ctx, `UPDATE spots SET like_count = GREATEST(like_count + ?, 0) WHERE id = ?`, delta, spotID); err != nil {
				return err
			}
		}
		return tx.QueryRowContext(ctx, `SELECT like_count FROM spots WHERE id = ?`, spotID).Scan(&count)
	})
	return count, err
}

// AddReport records a report. created is false when this user had already
// reported the target. At hideThreshold distinct reporters the target is hidden.
func (r repo) AddReport(ctx context.Context, userID uint64, targetType string, targetID uint64, reason string) (bool, error) {
	var table string
	switch targetType {
	case "spot":
		table = "spots"
	case "update":
		table = "spot_updates"
	case "review":
		table = "spot_reviews"
	default:
		return false, errBadType
	}
	created := false
	err := r.inTx(ctx, func(tx *sql.Tx) error {
		var x uint64
		lock := `SELECT id FROM ` + table + ` WHERE id = ?`
		if targetType == "review" {
			lock += ` AND status = 'active'`
		}
		err := tx.QueryRowContext(ctx, lock+` FOR UPDATE`, targetID).Scan(&x)
		if errors.Is(err, sql.ErrNoRows) {
			return errNotFound
		}
		if err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx,
			`INSERT IGNORE INTO reports (user_id, target_type, target_id, reason) VALUES (?, ?, ?, ?)`,
			userID, targetType, targetID, reason)
		if err != nil {
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n == 0 {
			return nil
		}
		created = true
		var distinct int
		if err := tx.QueryRowContext(ctx,
			`SELECT COUNT(DISTINCT user_id) FROM reports WHERE target_type = ? AND target_id = ?`,
			targetType, targetID).Scan(&distinct); err != nil {
			return err
		}
		if distinct >= hideThreshold {
			if _, err := tx.ExecContext(ctx, `UPDATE `+table+` SET status = 'hidden' WHERE id = ?`, targetID); err != nil {
				return err
			}
		}
		return nil
	})
	return created, err
}
