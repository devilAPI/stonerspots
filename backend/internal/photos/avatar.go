package photos

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"strings"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

// Avatars are one square JPEG per user in the photo storage, under keys
// starting with avatarPrefix. The key is kept in users.avatar_key only, never
// in photos: CleanupUnattached works on the photos table alone and so can
// never take an avatar. Every new avatar gets a new random key (media is
// served as immutable) and the old file is removed.
const avatarPrefix = "avatars/"

// ErrNoUser: there is no user with that id.
var ErrNoUser = errors.New("photos: no such user")

// SetAvatar makes key (already stored) the avatar of userID and returns the
// key it replaced ("" if none). The old file is not touched.
func SetAvatar(ctx context.Context, db *sql.DB, userID uint64, key string) (old string, err error) {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback() //nolint:errcheck
	var prev sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT avatar_key FROM users WHERE id = ? FOR UPDATE`, userID).Scan(&prev)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNoUser
	}
	if err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE users SET avatar_key = ? WHERE id = ?`, key, userID); err != nil {
		return "", err
	}
	return prev.String, tx.Commit()
}

// RemoveAvatar clears the avatar of userID and deletes its file. It is a
// no-op for a user without one; ErrNoUser for an unknown user.
func RemoveAvatar(ctx context.Context, db *sql.DB, storage Storage, userID uint64) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var prev sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT avatar_key FROM users WHERE id = ? FOR UPDATE`, userID).Scan(&prev)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNoUser
	}
	if err != nil {
		return err
	}
	if !prev.Valid {
		return nil
	}
	if _, err := tx.ExecContext(ctx, `UPDATE users SET avatar_key = NULL WHERE id = ?`, userID); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	deleteAvatarFile(ctx, storage, prev.String)
	return nil
}

// deleteAvatarFile removes an avatar file best-effort. Only keys below
// avatarPrefix are touched.
func deleteAvatarFile(ctx context.Context, storage Storage, key string) {
	if !strings.HasPrefix(key, avatarPrefix) || key == avatarPrefix {
		return
	}
	if err := storage.Delete(ctx, key); err != nil {
		log.Printf("photos: delete avatar file %q: %v", key, err)
	}
}

// putAvatar answers PUT /me/avatar: multipart field "photo", the same
// limits and types as POST /photos. 200 {"avatar_url": "..."}.
func (h *handler) putAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	f, ok := formFile(w, r, "photo")
	if !ok {
		return
	}
	defer r.MultipartForm.RemoveAll()
	defer f.Close()

	img, err := NormalizeAvatar(f, MaxUploadBytes)
	if !normalizeOK(w, err) {
		return
	}
	key, err := randomKey(".jpg")
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	key = avatarPrefix + key
	ctx := r.Context()
	if err := h.storage.Put(ctx, key, bytes.NewReader(img)); err != nil {
		log.Printf("photos: put avatar: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	old, err := SetAvatar(ctx, h.d.DB, uid, key)
	if err != nil {
		_ = h.storage.Delete(ctx, key)
		if errors.Is(err, ErrNoUser) {
			httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
			return
		}
		log.Printf("photos: set avatar: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	if old != "" {
		deleteAvatarFile(ctx, h.storage, old)
	}
	httpx.JSON(w, http.StatusOK, struct {
		AvatarURL string `json:"avatar_url"`
	}{h.storage.URL(key)})
}

// deleteAvatar answers DELETE /me/avatar: 204, also when there is none.
func (h *handler) deleteAvatar(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	switch err := RemoveAvatar(r.Context(), h.d.DB, h.storage, uid); {
	case errors.Is(err, ErrNoUser):
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
	case err != nil:
		log.Printf("photos: remove avatar: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
