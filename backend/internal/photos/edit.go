package photos

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"image"
	"log"
	"strings"

	"github.com/disintegration/imaging"
)

var (
	// ErrNotFound: no photo with that id.
	ErrNotFound = errors.New("photos: not found")
	// ErrInvalidRotation: degrees other than 90, 180 or 270.
	ErrInvalidRotation = errors.New("photos: invalid rotation")
	// ErrLastPhoto: removing it would leave its update with neither text
	// nor photos.
	ErrLastPhoto = errors.New("photos: last photo of an update without text")
)

// Rotated describes a photo after Rotate.
type Rotated struct {
	ID       uint64 `json:"id"`
	URL      string `json:"url"`
	ThumbURL string `json:"thumb_url"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
}

// Rotate turns a stored photo clockwise by degrees (90, 180 or 270). The
// result is written under new keys and the old files are removed: media is
// served as immutable, so overwriting a key would leave stale caches.
func Rotate(ctx context.Context, db *sql.DB, storage Storage, id uint64, degrees int) (Rotated, error) {
	var turn func(image.Image) *image.NRGBA
	switch degrees {
	case 90:
		turn = imaging.Rotate270 // imaging rotates counter-clockwise
	case 180:
		turn = imaging.Rotate180
	case 270:
		turn = imaging.Rotate90
	default:
		return Rotated{}, ErrInvalidRotation
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return Rotated{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	var oldKey, oldThumb string
	err = tx.QueryRowContext(ctx, "SELECT `key`, thumb_key FROM photos WHERE id = ? FOR UPDATE", id).Scan(&oldKey, &oldThumb)
	if errors.Is(err, sql.ErrNoRows) {
		return Rotated{}, ErrNotFound
	}
	if err != nil {
		return Rotated{}, err
	}
	f, err := storage.Open(ctx, oldKey)
	if err != nil {
		return Rotated{}, err
	}
	img, err := imaging.Decode(f)
	f.Close()
	if err != nil {
		return Rotated{}, err
	}
	fullImg := turn(img)
	full, err := encodeJPEG(fullImg)
	if err != nil {
		return Rotated{}, err
	}
	thumb, err := encodeJPEG(fit(fullImg, thumbMaxEdge))
	if err != nil {
		return Rotated{}, err
	}
	key, err := randomKey(".jpg")
	if err != nil {
		return Rotated{}, err
	}
	thumbKey := strings.TrimSuffix(key, ".jpg") + "_thumb.jpg"
	if err := storage.Put(ctx, key, bytes.NewReader(full)); err != nil {
		return Rotated{}, err
	}
	if err := storage.Put(ctx, thumbKey, bytes.NewReader(thumb)); err != nil {
		_ = storage.Delete(ctx, key)
		return Rotated{}, err
	}
	b := fullImg.Bounds()
	_, err = tx.ExecContext(ctx, "UPDATE photos SET `key` = ?, thumb_key = ?, width = ?, height = ? WHERE id = ?",
		key, thumbKey, b.Dx(), b.Dy(), id)
	if err == nil {
		err = tx.Commit()
	}
	if err != nil {
		_ = storage.Delete(ctx, key)
		_ = storage.Delete(ctx, thumbKey)
		return Rotated{}, err
	}
	removeBestEffort(ctx, storage, oldKey, oldThumb)
	return Rotated{ID: id, URL: storage.URL(key), ThumbURL: storage.URL(thumbKey), Width: b.Dx(), Height: b.Dy()}, nil
}

// Remove deletes a photo row and its files. The last photo of an update
// without text is refused (ErrLastPhoto): delete the update instead.
func Remove(ctx context.Context, db *sql.DB, storage Storage, id uint64) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	var key, thumbKey string
	var updateID sql.NullInt64
	err = tx.QueryRowContext(ctx, "SELECT `key`, thumb_key, update_id FROM photos WHERE id = ? FOR UPDATE", id).
		Scan(&key, &thumbKey, &updateID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if updateID.Valid {
		var body string
		var photos int
		err := tx.QueryRowContext(ctx,
			"SELECT u.body, (SELECT COUNT(*) FROM photos WHERE update_id = u.id) FROM spot_updates u WHERE u.id = ? FOR UPDATE",
			updateID.Int64).Scan(&body, &photos)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		if err == nil && strings.TrimSpace(body) == "" && photos <= 1 {
			return ErrLastPhoto
		}
	}
	if _, err := tx.ExecContext(ctx, "DELETE FROM photos WHERE id = ?", id); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	removeBestEffort(ctx, storage, key, thumbKey)
	return nil
}

func removeBestEffort(ctx context.Context, storage Storage, keys ...string) {
	for _, k := range keys {
		if err := storage.Delete(ctx, k); err != nil {
			log.Printf("photos: remove %s: %v", k, err)
		}
	}
}
