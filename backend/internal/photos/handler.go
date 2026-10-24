package photos

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net/http"
	"path/filepath"
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

func (h *handler) upload(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	// Allow a little overhead for multipart framing; the file itself is capped in Normalize.
	r.Body = http.MaxBytesReader(w, r.Body, MaxUploadBytes+(1<<20))
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "photo must be at most 8 MB")
			return
		}
		httpx.Error(w, http.StatusBadRequest, "file_required", "multipart field 'file' is required")
		return
	}
	defer r.MultipartForm.RemoveAll()
	f, _, err := r.FormFile("file")
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "file_required", "multipart field 'file' is required")
		return
	}
	defer f.Close()

	full, thumb, width, height, err := Normalize(f, MaxUploadBytes)
	switch {
	case errors.Is(err, ErrTooLarge):
		httpx.Error(w, http.StatusRequestEntityTooLarge, "too_large", "photo must be at most 8 MB")
		return
	case errors.Is(err, ErrUnsupported):
		httpx.Error(w, http.StatusUnsupportedMediaType, "unsupported_type", "only JPEG, PNG, WebP and AVIF images are accepted")
		return
	case err != nil:
		log.Printf("photos: normalize: %v", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not process photo")
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

// serveMedia serves files from the upload dir. Only plain relative keys are allowed.
func (h *handler) serveMedia(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/v1/media/")
	if i := strings.Index(r.URL.Path, "/media/"); i >= 0 {
		rest = r.URL.Path[i+len("/media/"):]
	}
	if rest == "" || strings.Contains(rest, "..") || strings.ContainsAny(rest, "\\\x00") || !strings.HasSuffix(rest, ".jpg") {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeFile(w, r, filepath.Join(h.d.Cfg.UploadDir, filepath.FromSlash(rest)))
}
