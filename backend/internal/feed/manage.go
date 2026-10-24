package feed

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

var (
	errNotFound  = errors.New("feed: update not found")
	errForbidden = errors.New("feed: not the author")
)

// lockOwn locks an active update and checks that userID wrote it.
func lockOwn(ctx context.Context, tx *sql.Tx, id, userID uint64) (body string, err error) {
	var owner uint64
	err = tx.QueryRowContext(ctx, "SELECT user_id, body FROM spot_updates WHERE id = ? AND status = 'active' FOR UPDATE", id).Scan(&owner, &body)
	if errors.Is(err, sql.ErrNoRows) {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	if owner != userID {
		return "", errForbidden
	}
	return body, nil
}

// editUpdate applies a partial edit (nil = unchanged) by the update's author.
func editUpdate(ctx context.Context, db *sql.DB, id, userID uint64, body, tag *string) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	cur, err := lockOwn(ctx, tx, id, userID)
	if err != nil {
		return err
	}
	if tag != nil && !ValidTag(*tag) {
		return ErrInvalidTag
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
	if _, err := tx.ExecContext(ctx,
		"UPDATE spot_updates SET body = ?, tag = COALESCE(?, tag), edited_at = CURRENT_TIMESTAMP WHERE id = ?", newBody, tag, id); err != nil {
		return err
	}
	return tx.Commit()
}

// deleteUpdate removes the update, its photo rows and its reports, then the
// photo files best-effort.
func deleteUpdate(ctx context.Context, db *sql.DB, uploadDir string, id, userID uint64) error {
	return removeUpdate(ctx, db, uploadDir, id, &userID)
}

// removeUpdate is the shared delete. With ownerID set only the author may
// delete an active update; nil (admin) deletes any update.
func removeUpdate(ctx context.Context, db *sql.DB, uploadDir string, id uint64, ownerID *uint64) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	if ownerID != nil {
		if _, err := lockOwn(ctx, tx, id, *ownerID); err != nil {
			return err
		}
	} else {
		var one uint64
		err := tx.QueryRowContext(ctx, "SELECT id FROM spot_updates WHERE id = ? FOR UPDATE", id).Scan(&one)
		if errors.Is(err, sql.ErrNoRows) {
			return errNotFound
		}
		if err != nil {
			return err
		}
	}
	rows, err := tx.QueryContext(ctx, "SELECT `key`, thumb_key FROM photos WHERE update_id = ?", id)
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
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, q := range []string{
		"DELETE FROM photos WHERE update_id = ?",
		"DELETE FROM reports WHERE target_type = 'update' AND target_id = ?",
		"DELETE FROM spot_updates WHERE id = ?",
	} {
		if _, err := tx.ExecContext(ctx, q, id); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	removeFiles(uploadDir, keys)
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

func updateID(w http.ResponseWriter, r *http.Request) (uint64, uint64, bool) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return 0, 0, false
	}
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "update not found")
		return 0, 0, false
	}
	return uid, id, true
}

// manageError writes the shared error responses; it returns true if err was handled.
func manageError(w http.ResponseWriter, err error) {
	switch {
	case err == nil:
	case errors.Is(err, errNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "update not found")
	case errors.Is(err, errForbidden):
		httpx.Error(w, http.StatusForbidden, "forbidden", "only the author can change this update")
	case errors.Is(err, ErrInvalidTag):
		httpx.Error(w, http.StatusBadRequest, "invalid_tag", "tag must be one of note, still_good, crowded, dirty, closed")
	case errors.Is(err, ErrInvalidBody):
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "body must be at most 2000 characters; text or photos required")
	default:
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
	}
}

func (h *handler) patchUpdate(w http.ResponseWriter, r *http.Request) {
	uid, id, ok := updateID(w, r)
	if !ok {
		return
	}
	var raw map[string]json.RawMessage
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&raw); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	if raw == nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "request body must be a JSON object")
		return
	}
	var body, tag *string
	for k, v := range raw {
		switch k {
		case "body", "tag":
			var s string
			if err := json.Unmarshal(v, &s); err != nil {
				code := "invalid_body"
				if k == "tag" {
					code = "invalid_tag"
				}
				httpx.Error(w, http.StatusBadRequest, code, k+" must be a string")
				return
			}
			if k == "body" {
				body = &s
			} else {
				tag = &s
			}
		}
	}
	if body == nil && tag == nil {
		httpx.Error(w, http.StatusBadRequest, "empty_patch", "provide body and/or tag")
		return
	}
	if err := editUpdate(r.Context(), h.db, id, uid, body, tag); err != nil {
		manageError(w, err)
		return
	}
	it, err := getItem(r.Context(), h.db, h.base, id)
	if err != nil {
		manageError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, it)
}

func (h *handler) deleteUpdate(w http.ResponseWriter, r *http.Request) {
	uid, id, ok := updateID(w, r)
	if !ok {
		return
	}
	if err := deleteUpdate(r.Context(), h.db, h.uploadDir, id, uid); err != nil {
		manageError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
