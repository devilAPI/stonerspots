package auth

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/httpx"
)

var (
	errWrongPassword = errors.New("wrong password")
	errNoUser        = errors.New("user not found")
)

// checkPassword verifies the user's current password. It returns errNoUser if
// the user row no longer exists and errWrongPassword on a mismatch.
func (s *service) checkPassword(ctx context.Context, userID uint64, password string) (*User, error) {
	var u User
	var hash string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, email, display_name, is_admin, password_hash FROM users WHERE id = ?`, userID,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.IsAdmin, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errNoUser
	}
	if err != nil {
		return nil, err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return nil, errWrongPassword
	}
	return &u, nil
}

// changePassword sets a new password, revokes every refresh token of the user
// and returns a fresh session (new token family).
func (s *service) changePassword(ctx context.Context, userID uint64, current, next string) (*Session, error) {
	u, err := s.checkPassword(ctx, userID, current)
	if err != nil {
		return nil, err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(next), bcryptCost)
	if err != nil {
		return nil, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback() //nolint:errcheck
	if _, err := tx.ExecContext(ctx, `UPDATE users SET password_hash = ? WHERE id = ?`, string(hash), userID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL`,
		time.Now().UTC(), userID); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return s.session(ctx, *u, "")
}

// deleteAccount deletes the user (cascading to all owned rows) in one
// transaction and then removes their photo files best-effort.
func (s *service) deleteAccount(ctx context.Context, userID uint64, password string) error {
	if _, err := s.checkPassword(ctx, userID, password); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	rows, err := tx.QueryContext(ctx, "SELECT `key`, thumb_key FROM photos WHERE user_id = ?", userID)
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
	// Reports are polymorphic (no FK): drop those about the user's spots and
	// everything below them, and their own updates/reviews, before the cascade.
	const mySpots = `(SELECT id FROM spots WHERE user_id = ?)`
	if _, err := tx.ExecContext(ctx, `DELETE FROM reports WHERE
		(target_type = 'spot' AND target_id IN `+mySpots+`)
		OR (target_type = 'update' AND target_id IN (SELECT id FROM spot_updates WHERE user_id = ? OR spot_id IN `+mySpots+`))
		OR (target_type = 'review' AND target_id IN (SELECT id FROM spot_reviews WHERE user_id = ? OR spot_id IN `+mySpots+`))`,
		userID, userID, userID, userID, userID); err != nil {
		return err
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM users WHERE id = ?`, userID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return errNoUser
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	removeFiles(s.uploadDir, keys)
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

func (h *handler) accountError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errNoUser):
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
	case errors.Is(err, errWrongPassword):
		httpx.Error(w, http.StatusForbidden, "wrong_password", "current password is incorrect")
	default:
		serverError(w)
	}
}

func (h *handler) changePassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	id, _ := UserID(r.Context())
	if len(in.NewPassword) < 10 || len(in.NewPassword) > 72 || in.NewPassword == in.CurrentPassword {
		// Existence check first so a deleted user gets 401, not 400.
		if _, err := h.svc.user(r.Context(), id); err != nil {
			h.accountError(w, errNoUser)
			return
		}
		httpx.Error(w, http.StatusBadRequest, "invalid_password", "new password must be 10 to 72 bytes long and differ from the current one")
		return
	}
	s, err := h.svc.changePassword(r.Context(), id, in.CurrentPassword, in.NewPassword)
	if err != nil {
		h.accountError(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, s)
}

func (h *handler) deleteAccount(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string `json:"password"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	id, _ := UserID(r.Context())
	if err := h.svc.deleteAccount(r.Context(), id, in.Password); err != nil {
		h.accountError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
