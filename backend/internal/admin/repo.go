package admin

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"stonerspots/backend/internal/spots/tagset"
)

var errNotFound = errors.New("not found")

type repo struct {
	db        *sql.DB
	uploadDir string
}

type person struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

type reporter struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
	Email       string `json:"email"`
}

type reportTarget struct {
	Exists bool    `json:"exists"`
	SpotID uint64  `json:"spot_id,omitempty"`
	Title  string  `json:"title,omitempty"`
	Status string  `json:"status,omitempty"`
	Body   string  `json:"body"`
	Rating int     `json:"rating"`
	Author *person `json:"author,omitempty"`
}

type reportItem struct {
	ID          uint64       `json:"id"`
	TargetType  string       `json:"target_type"`
	TargetID    uint64       `json:"target_id"`
	Reason      string       `json:"reason"`
	CreatedAt   time.Time    `json:"created_at"`
	ReportCount int          `json:"report_count"`
	Reporter    reporter     `json:"reporter"`
	Target      reportTarget `json:"target"`
}

// likeEscape escapes LIKE wildcards so user input matches literally.
func likeEscape(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
}

func (r repo) reports(ctx context.Context, limit int, after uint64) ([]reportItem, error) {
	q := `SELECT r.id, r.target_type, r.target_id, r.reason, r.created_at,
		(SELECT COUNT(DISTINCT r2.user_id) FROM reports r2 WHERE r2.target_type = r.target_type AND r2.target_id = r.target_id),
		ru.id, ru.display_name, ru.email,
		s.id, s.title, IF(r.target_type = 'review', rv.status, s.status), COALESCE(up.id, rv.id),
		COALESCE(up.body, rv.body), COALESCE(rv.rating, 0), au.id, au.display_name
	FROM reports r
	JOIN users ru ON ru.id = r.user_id
	LEFT JOIN spot_updates up ON r.target_type = 'update' AND up.id = r.target_id
	LEFT JOIN spot_reviews rv ON r.target_type = 'review' AND rv.id = r.target_id
	LEFT JOIN spots s ON s.id = CASE r.target_type WHEN 'spot' THEN r.target_id WHEN 'update' THEN up.spot_id ELSE rv.spot_id END
	LEFT JOIN users au ON au.id = CASE r.target_type WHEN 'spot' THEN s.user_id WHEN 'update' THEN up.user_id ELSE rv.user_id END
	WHERE (? = 0 OR r.id < ?)
	ORDER BY r.id DESC LIMIT ?`
	rows, err := r.db.QueryContext(ctx, q, after, after, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []reportItem
	for rows.Next() {
		var it reportItem
		var (
			spotID, subID, authorID  sql.NullInt64
			title, status, body, aun sql.NullString
			rating                   int
		)
		if err := rows.Scan(&it.ID, &it.TargetType, &it.TargetID, &it.Reason, &it.CreatedAt, &it.ReportCount,
			&it.Reporter.ID, &it.Reporter.DisplayName, &it.Reporter.Email,
			&spotID, &title, &status, &subID, &body, &rating, &authorID, &aun); err != nil {
			return nil, err
		}
		it.CreatedAt = it.CreatedAt.UTC()
		exists := spotID.Valid && (it.TargetType == "spot" || subID.Valid)
		if exists {
			it.Target = reportTarget{Exists: true, SpotID: uint64(spotID.Int64), Title: title.String,
				Status: status.String, Body: body.String, Rating: rating}
			if authorID.Valid {
				it.Target.Author = &person{ID: uint64(authorID.Int64), DisplayName: aun.String}
			}
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

type userItem struct {
	ID              uint64    `json:"id"`
	Email           string    `json:"email"`
	DisplayName     string    `json:"display_name"`
	IsAdmin         bool      `json:"is_admin"`
	Banned          bool      `json:"banned"`
	CreatedAt       time.Time `json:"created_at"`
	SpotCount       int       `json:"spot_count"`
	ReportsReceived int       `json:"reports_received"`
}

const userSelect = `SELECT u.id, u.email, u.display_name, u.is_admin, u.banned_at IS NOT NULL, u.created_at,
		(SELECT COUNT(*) FROM spots s WHERE s.user_id = u.id),
		(SELECT COUNT(*) FROM reports r JOIN spots s ON r.target_type = 'spot' AND r.target_id = s.id WHERE s.user_id = u.id)
		+ (SELECT COUNT(*) FROM reports r JOIN spot_updates su ON r.target_type = 'update' AND r.target_id = su.id WHERE su.user_id = u.id)
		+ (SELECT COUNT(*) FROM reports r JOIN spot_reviews sr ON r.target_type = 'review' AND r.target_id = sr.id WHERE sr.user_id = u.id)
	FROM users u `

func scanUser(row interface{ Scan(...any) error }) (userItem, error) {
	var it userItem
	err := row.Scan(&it.ID, &it.Email, &it.DisplayName, &it.IsAdmin, &it.Banned, &it.CreatedAt, &it.SpotCount, &it.ReportsReceived)
	it.CreatedAt = it.CreatedAt.UTC()
	return it, err
}

func (r repo) users(ctx context.Context, search string, limit int, after uint64) ([]userItem, error) {
	q := userSelect + `
	WHERE (? = 0 OR u.id < ?)
	  AND (? = '' OR u.email LIKE ? ESCAPE '\\' OR u.display_name LIKE ? ESCAPE '\\')
	ORDER BY u.id DESC LIMIT ?`
	pat := "%" + likeEscape(search) + "%"
	rows, err := r.db.QueryContext(ctx, q, after, after, search, pat, pat, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []userItem
	for rows.Next() {
		it, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

type spotItem struct {
	ID          uint64    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Lat         float64   `json:"lat"`
	Lon         float64   `json:"lon"`
	Status      string    `json:"status"`
	LikeCount   int       `json:"like_count"`
	CreatedAt   time.Time `json:"created_at"`
	Author      person    `json:"author"`
	ReportCount int       `json:"report_count"`
	Tags        []string  `json:"tags"`
	Locked      bool      `json:"locked"`
}

const spotSelect = `SELECT s.id, s.title, s.description, ST_Y(s.location), ST_X(s.location), s.status, s.locked, s.like_count, s.created_at,
		u.id, u.display_name,
		(SELECT COUNT(DISTINCT r.user_id) FROM reports r WHERE r.target_type = 'spot' AND r.target_id = s.id)
	FROM spots s JOIN users u ON u.id = s.user_id `

func scanSpot(row interface{ Scan(...any) error }) (spotItem, error) {
	var it spotItem
	err := row.Scan(&it.ID, &it.Title, &it.Description, &it.Lat, &it.Lon, &it.Status, &it.Locked, &it.LikeCount, &it.CreatedAt,
		&it.Author.ID, &it.Author.DisplayName, &it.ReportCount)
	it.CreatedAt = it.CreatedAt.UTC()
	it.Tags = []string{}
	return it, err
}

func (r repo) spots(ctx context.Context, search, status string, limit int, after uint64) ([]spotItem, error) {
	q := spotSelect + `
	WHERE (? = 0 OR s.id < ?)
	  AND (? = '' OR s.title LIKE ? ESCAPE '\\')
	  AND (? = '' OR s.status = ?)
	ORDER BY s.id DESC LIMIT ?`
	pat := "%" + likeEscape(search) + "%"
	rows, err := r.db.QueryContext(ctx, q, after, after, search, pat, status, status, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []spotItem
	for rows.Next() {
		it, err := scanSpot(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	ids := make([]uint64, len(out))
	for i, it := range out {
		ids[i] = it.ID
	}
	tags, err := tagset.Load(ctx, r.db, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		if t := tags[out[i].ID]; t != nil {
			out[i].Tags = t
		}
	}
	return out, nil
}

// deleteSpot removes the spot with its updates (FK cascade), the photo rows of
// those updates (their FK is SET NULL, so they are deleted explicitly), likes
// (cascade) and all reports pointing at the spot or its updates (polymorphic,
// no FK) in one transaction; the photo files are removed best-effort afterwards.
func (r repo) deleteSpot(ctx context.Context, id uint64) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var one uint64
	err = tx.QueryRowContext(ctx, `SELECT id FROM spots WHERE id = ? FOR UPDATE`, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return errNotFound
	}
	if err != nil {
		return err
	}
	const updates = `(SELECT id FROM spot_updates WHERE spot_id = ?)`
	rows, err := tx.QueryContext(ctx, "SELECT `key`, thumb_key FROM photos WHERE update_id IN "+updates, id)
	if err != nil {
		return err
	}
	var keys []string
	for rows.Next() {
		var k, tk string
		if err := rows.Scan(&k, &tk); err != nil {
			rows.Close()
			return err
		}
		keys = append(keys, k, tk)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()
	for _, s := range []struct {
		q    string
		args []any
	}{
		{"DELETE FROM photos WHERE update_id IN " + updates, []any{id}},
		{"DELETE FROM reports WHERE (target_type = 'spot' AND target_id = ?) OR (target_type = 'update' AND target_id IN " + updates + ") OR (target_type = 'review' AND target_id IN (SELECT id FROM spot_reviews WHERE spot_id = ?))", []any{id, id, id}},
		{"DELETE FROM spots WHERE id = ?", []any{id}},
	} {
		if _, err := tx.ExecContext(ctx, s.q, s.args...); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	removeFiles(r.uploadDir, keys)
	return nil
}

// removeFiles deletes files below dir, best-effort. Unsafe keys are skipped.
func removeFiles(dir string, keys []string) {
	if dir == "" {
		return
	}
	for _, k := range keys {
		if k == "" || strings.Contains(k, "..") || strings.HasPrefix(k, "/") || strings.HasPrefix(k, `\`) || filepath.IsAbs(k) {
			continue
		}
		_ = os.Remove(filepath.Join(dir, filepath.FromSlash(k)))
	}
}
