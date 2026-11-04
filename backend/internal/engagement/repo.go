package engagement

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"time"

	"stonerspots/backend/internal/activity"
)

var (
	errNotFound = errors.New("not found")
	errBadType  = errors.New("invalid target type")
)

// Auto-hide. Reported content is hidden at once when enough trusted
// accounts have reported it; admins still see every report (GET
// /admin/reports) and can restore it. A reporter is trusted when the
// account
//   - is at least trustedAge old and not banned,
//   - has a verified email address, when mail (and so verification) is on,
//   - has at least one contribution others can see: an active spot, spot
//     update or review.
//
// So a burst of fresh throwaway accounts cannot hide anything; their
// reports still reach the admins. Spots, which carry the most content,
// need more trusted reporters than single updates, reviews and comments.
const (
	trustedAge        = 7 * 24 * time.Hour
	hideThresholdSpot = 5
	hideThreshold     = 3
)

type repo struct {
	db *sql.DB
	// requireVerified: only reporters with a verified email count (mail on)
	requireVerified bool
}

func threshold(targetType string) int {
	if targetType == "spot" {
		return hideThresholdSpot
	}
	return hideThreshold
}

// trustedReporters counts the distinct trusted accounts (see above) that
// reported the target.
func (r repo) trustedReporters(ctx context.Context, tx *sql.Tx, targetType string, targetID uint64) (int, error) {
	var n int
	err := tx.QueryRowContext(ctx, `SELECT COUNT(DISTINCT rp.user_id)
		FROM reports rp JOIN users u ON u.id = rp.user_id
		WHERE rp.target_type = ? AND rp.target_id = ?
		  AND u.banned_at IS NULL
		  AND u.created_at <= NOW() - INTERVAL ? SECOND
		  AND (? = 0 OR u.email_verified = 1)
		  AND (EXISTS (SELECT 1 FROM spots s WHERE s.user_id = u.id AND s.status = 'active')
		    OR EXISTS (SELECT 1 FROM spot_updates su WHERE su.user_id = u.id AND su.status = 'active')
		    OR EXISTS (SELECT 1 FROM spot_reviews rv WHERE rv.user_id = u.id AND rv.status = 'active'))`,
		targetType, targetID, int64(trustedAge/time.Second), r.requireVerified).Scan(&n)
	return n, err
}

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
// returns its owner, or errNotFound if it does not exist.
func lockSpot(ctx context.Context, tx *sql.Tx, id uint64) (uint64, error) {
	var owner uint64
	err := tx.QueryRowContext(ctx, `SELECT user_id FROM spots WHERE id = ? FOR UPDATE`, id).Scan(&owner)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, errNotFound
	}
	return owner, err
}

// SetLike adds or removes the like and keeps spots.like_count equal to the
// number of spot_likes rows. A new like tells the spot's author through their
// activity; removing it takes the unread notice back. It returns the resulting count.
func (r repo) SetLike(ctx context.Context, userID, spotID uint64, liked bool) (int, error) {
	var count int
	err := r.inTx(ctx, func(tx *sql.Tx) error {
		owner, err := lockSpot(ctx, tx, spotID)
		if err != nil {
			return err
		}
		var res sql.Result
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
		ev := activity.Event{Recipient: owner, Actor: userID, Kind: activity.Like, SpotID: spotID}
		if liked && n > 0 {
			err = activity.Add(ctx, tx, ev)
		} else if !liked {
			err = activity.RemoveUnread(ctx, tx, ev)
		}
		if err != nil {
			return err
		}
		return tx.QueryRowContext(ctx, `SELECT like_count FROM spots WHERE id = ?`, spotID).Scan(&count)
	})
	return count, err
}

// AddReport records a report. created is false when this user had already
// reported the target. When enough trusted reporters (see threshold) have
// reported it, the target is hidden.
func (r repo) AddReport(ctx context.Context, userID uint64, targetType string, targetID uint64, reason string) (bool, error) {
	var table string
	switch targetType {
	case "spot":
		table = "spots"
	case "update":
		table = "spot_updates"
	case "review":
		table = "spot_reviews"
	case "comment":
		table = "comments"
	default:
		return false, errBadType
	}
	created := false
	err := r.inTx(ctx, func(tx *sql.Tx) error {
		var x uint64
		lock := `SELECT id FROM ` + table + ` WHERE id = ?`
		if targetType == "review" || targetType == "comment" {
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
		trusted, err := r.trustedReporters(ctx, tx, targetType, targetID)
		if err != nil {
			return err
		}
		if trusted >= threshold(targetType) {
			res, err := tx.ExecContext(ctx, `UPDATE `+table+` SET status = 'hidden' WHERE id = ? AND status = 'active'`, targetID)
			if err != nil {
				return err
			}
			if n, _ := res.RowsAffected(); n == 1 {
				log.Printf("auto_hide target=%s id=%d trusted_reporters=%d", targetType, targetID, trusted)
			}
		}
		return nil
	})
	return created, err
}
