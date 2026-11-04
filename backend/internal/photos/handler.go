package photos

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

type handler struct {
	d       app.Deps
	storage Storage
}

type uploadResponse struct {
	ID       uint64 `json:"id"`
	URL      string `json:"url"`
	ThumbURL string `json:"thumb_url"`
}

func randomKey(ext string) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	now := time.Now().UTC()
	return fmt.Sprintf("%04d/%02d/%s%s", now.Year(), int(now.Month()), hex.EncodeToString(b), ext), nil
}

// formFile reads the multipart upload in field, with the photo size limit.
// It writes the error response itself when it returns false; otherwise the
// caller must close the file and call r.MultipartForm.RemoveAll.
func formFile(w http.ResponseWriter, r *http.Request, field string) (multipart.File, bool) {
	// Allow a little overhead for multipart framing; the file itself is capped in Normalize.
	r.Body = http.MaxBytesReader(w, r.Body, MaxUploadBytes+(1<<20))
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "photo must be at most 8 MB")
			return nil, false
		}
		httpx.Error(w, http.StatusBadRequest, "file_required", "multipart field '"+field+"' is required")
		return nil, false
	}
	f, _, err := r.FormFile(field)
	if err != nil {
		r.MultipartForm.RemoveAll()
		httpx.Error(w, http.StatusBadRequest, "file_required", "multipart field '"+field+"' is required")
		return nil, false
	}
	return f, true
}

// busyRetryAfter is the Retry-After, in seconds, of a 503 busy answer.
const busyRetryAfter = 10

// normalizeOK maps an error of Normalize or NormalizeAvatar to its response
// and reports whether there was none.
func normalizeOK(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return true
	case errors.Is(err, ErrTooLarge):
		httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "photo must be at most 8 MB")
	case errors.Is(err, ErrUnsupported):
		httpx.Error(w, http.StatusUnsupportedMediaType, "unsupported_type", "only JPEG, PNG, WebP and AVIF images are accepted")
	case errors.Is(err, ErrBusy), errors.Is(err, context.Canceled), errors.Is(err, context.DeadlineExceeded):
		// no decode slot in time (or the client is gone): try again later
		w.Header().Set("Retry-After", strconv.Itoa(busyRetryAfter))
		httpx.Error(w, http.StatusServiceUnavailable, "busy", "too many photos are being processed, try again in a moment")
	default:
		log.Printf("photos: normalize: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not process photo")
	}
	return false
}

func (h *handler) upload(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	f, ok := formFile(w, r, "file")
	if !ok {
		return
	}
	defer r.MultipartForm.RemoveAll()
	defer f.Close()

	full, thumb, width, height, err := Normalize(r.Context(), f, MaxUploadBytes)
	if !normalizeOK(w, err) {
		return
	}

	key, err := randomKey(".jpg")
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	thumbKey := strings.TrimSuffix(key, ".jpg") + "_thumb.jpg"
	ctx := r.Context()
	if err := h.storage.Put(ctx, key, bytes.NewReader(full)); err != nil {
		log.Printf("photos: put: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	if err := h.storage.Put(ctx, thumbKey, bytes.NewReader(thumb)); err != nil {
		_ = h.storage.Delete(ctx, key)
		log.Printf("photos: put thumb: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	res, err := h.d.DB.ExecContext(ctx,
		"INSERT INTO photos (user_id, `key`, thumb_key, width, height) VALUES (?, ?, ?, ?, ?)",
		uid, key, thumbKey, width, height)
	if err != nil {
		_ = h.storage.Delete(ctx, key)
		_ = h.storage.Delete(ctx, thumbKey)
		log.Printf("photos: insert: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store photo")
		return
	}
	id, _ := res.LastInsertId()
	httpx.JSON(w, http.StatusCreated, uploadResponse{ID: uint64(id), URL: h.storage.URL(key), ThumbURL: h.storage.URL(thumbKey)})
}

// mediaCacheControl: keys are random and change with every new version
// (rotate, new avatar), but a photo that is hidden, rejected or deleted must
// stop being served from caches in reasonable time, so no year-long
// "immutable".
const mediaCacheControl = "public, max-age=3600"

// visiblePhoto finds a photo (by the column given, `key` or thumb_key) that
// is approved and attached to an active update on an active spot.
// Unattached photos (just uploaded, or of a deleted update: the foreign key
// sets update_id to NULL) are served to nobody; the app shows a pick from
// the device until its update is posted.
const visiblePhoto = `SELECT 1 FROM photos p
  JOIN spot_updates u ON u.id = p.update_id
  JOIN spots s ON s.id = u.spot_id
  WHERE p.%s = ? AND p.status = 'approved' AND u.status = 'active' AND s.status = 'active'`

// serveMedia serves files from the upload dir. Only plain relative keys are
// allowed, and only of visible content: the current avatar of a user, or a
// photo visiblePhoto finds. Anything else is a 404.
func (h *handler) serveMedia(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v1/media/")
	if i := strings.Index(r.URL.Path, "/media/"); i >= 0 {
		rest = r.URL.Path[i+len("/media/"):]
	}
	if rest == "" || strings.Contains(rest, "..") || strings.ContainsAny(rest, "\\\x00") || !strings.HasSuffix(rest, ".jpg") {
		http.NotFound(w, r)
		return
	}
	var q string
	switch {
	case strings.HasPrefix(rest, avatarPrefix):
		// a user's current avatar (users.avatar_key, see avatar.go)
		q = "SELECT 1 FROM users WHERE avatar_key = ?"
	case strings.HasSuffix(rest, "_thumb.jpg"):
		// thumb keys are "<key without .jpg>_thumb.jpg" (see upload); one
		// column per query, so each lookup uses its unique index
		q = fmt.Sprintf(visiblePhoto, "thumb_key")
	default:
		q = fmt.Sprintf(visiblePhoto, "`key`")
	}
	var one int
	if err := h.d.DB.QueryRowContext(r.Context(), q, rest).Scan(&one); err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			log.Printf("photos: serveMedia check: %v", err)
		}
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", mediaCacheControl)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeFile(w, r, filepath.Join(h.d.Cfg.UploadDir, filepath.FromSlash(rest)))
}
