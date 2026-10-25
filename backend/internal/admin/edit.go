package admin

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/go-sql-driver/mysql"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/reviews"
	"stonerspots/backend/internal/spots"
	"stonerspots/backend/internal/spots/tagset"
)

var (
	errEmailTaken   = errors.New("email taken")
	errCannotDemote = errors.New("cannot demote self")
	errLastAdmin    = errors.New("last admin")
)

func badBody(w http.ResponseWriter) {
	httpx.Error(w, http.StatusBadRequest, "invalid_body", "request body is not a valid JSON object of the expected types")
}

func notFound(w http.ResponseWriter, what string) {
	httpx.Error(w, http.StatusNotFound, "not_found", what+" not found")
}

func pathID(r *http.Request) (uint64, bool) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	return id, err == nil
}

// readPatch decodes a JSON object body into its raw fields, keeping only the
// keys in known. It writes the 400 itself (invalid_body for non-objects and
// null values, empty_patch when no known key is present).
func readPatch(w http.ResponseWriter, r *http.Request, known ...string) (map[string]json.RawMessage, bool) {
	var all map[string]json.RawMessage
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&all); err != nil || all == nil {
		badBody(w)
		return nil, false
	}
	out := map[string]json.RawMessage{}
	for _, k := range known {
		raw, ok := all[k]
		if !ok {
			continue
		}
		if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			badBody(w)
			return nil, false
		}
		out[k] = raw
	}
	if len(out) == 0 {
		httpx.Error(w, http.StatusBadRequest, "empty_patch", "no known field to change was sent")
		return nil, false
	}
	return out, true
}

func field[T any](p map[string]json.RawMessage, key string, dst *T) (present, ok bool) {
	raw, present := p[key]
	if !present {
		return false, true
	}
	return true, json.Unmarshal(raw, dst) == nil
}

// ---- users ----

type userPatch struct {
	displayName *string
	email       *string
	isAdmin     *bool
}

func (h handler) patchUser(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "user")
		return
	}
	caller, _ := auth.UserID(r.Context())
	p, ok := readPatch(w, r, "display_name", "email", "is_admin")
	if !ok {
		return
	}
	var up userPatch
	var s string
	var b bool
	if present, good := field(p, "display_name", &s); !good {
		badBody(w)
		return
	} else if present {
		s = strings.TrimSpace(s)
		if n := utf8.RuneCountInString(s); n < 1 || n > 80 {
			httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display name must be 1 to 80 characters")
			return
		}
		up.displayName = &s
	}
	var e string
	if present, good := field(p, "email", &e); !good {
		badBody(w)
		return
	} else if present {
		e = auth.NormalizeEmail(e)
		if !auth.ValidEmail(e) {
			httpx.Error(w, http.StatusBadRequest, "invalid_email", "email address is invalid")
			return
		}
		up.email = &e
	}
	if present, good := field(p, "is_admin", &b); !good {
		badBody(w)
		return
	} else if present {
		up.isAdmin = &b
	}
	it, err := h.repo.patchUser(r.Context(), id, caller, up)
	switch {
	case errors.Is(err, errNotFound):
		notFound(w, "user")
	case errors.Is(err, errEmailTaken):
		httpx.Error(w, http.StatusConflict, "email_taken", "email is already registered")
	case errors.Is(err, errCannotDemote):
		httpx.Error(w, http.StatusBadRequest, "cannot_demote_self", "you cannot remove your own admin flag")
	case errors.Is(err, errLastAdmin):
		httpx.Error(w, http.StatusBadRequest, "last_admin", "the last remaining admin cannot be demoted")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, it)
	}
}

func (r repo) patchUser(ctx context.Context, id, caller uint64, p userPatch) (userItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return userItem{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	demote := p.isAdmin != nil && !*p.isAdmin
	if demote {
		// Lock every admin row first (in id order) so that concurrent
		// demotions serialize without deadlocking and see each other's result.
		if _, err := tx.ExecContext(ctx, `SELECT id FROM users WHERE is_admin = 1 ORDER BY id FOR UPDATE`); err != nil {
			return userItem{}, err
		}
	}
	var isAdmin bool
	err = tx.QueryRowContext(ctx, `SELECT is_admin FROM users WHERE id = ? FOR UPDATE`, id).Scan(&isAdmin)
	if errors.Is(err, sql.ErrNoRows) {
		return userItem{}, errNotFound
	}
	if err != nil {
		return userItem{}, err
	}
	if demote && isAdmin {
		if id == caller {
			return userItem{}, errCannotDemote
		}
		var others int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE is_admin = 1 AND id <> ?`, id).Scan(&others); err != nil {
			return userItem{}, err
		}
		if others == 0 {
			return userItem{}, errLastAdmin
		}
	}
	if demote && !isAdmin && id == caller {
		return userItem{}, errCannotDemote
	}
	var sets []string
	var args []any
	if p.displayName != nil {
		sets, args = append(sets, "display_name = ?"), append(args, *p.displayName)
	}
	if p.email != nil {
		sets, args = append(sets, "email = ?"), append(args, *p.email)
	}
	if p.isAdmin != nil {
		sets, args = append(sets, "is_admin = ?"), append(args, *p.isAdmin)
	}
	if _, err := tx.ExecContext(ctx, "UPDATE users SET "+strings.Join(sets, ", ")+" WHERE id = ?", append(args, id)...); err != nil {
		var me *mysql.MySQLError
		if errors.As(err, &me) && me.Number == 1062 {
			return userItem{}, errEmailTaken
		}
		return userItem{}, err
	}
	it, err := scanUser(tx.QueryRowContext(ctx, userSelect+`WHERE u.id = ?`, id))
	if err != nil {
		return userItem{}, err
	}
	return it, tx.Commit()
}

// ---- spots ----

type spotPatch struct {
	title, description, status *string
	lat, lon                   *float64
	tags                       *[]string
	ownerID                    *uint64
	locked                     *bool
}

var errNoSuchOwner = errors.New("no such owner")

func (h handler) patchSpot(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "spot")
		return
	}
	p, ok := readPatch(w, r, "title", "description", "status", "lat", "lon", "tags", "owner_id", "locked")
	if !ok {
		return
	}
	var sp spotPatch
	str := func(key string, dst **string) bool {
		var v string
		present, good := field(p, key, &v)
		if !good {
			badBody(w)
			return false
		}
		if present {
			*dst = &v
		}
		return true
	}
	if !str("title", &sp.title) || !str("description", &sp.description) || !str("status", &sp.status) {
		return
	}
	var lat, lon float64
	latPresent, good := field(p, "lat", &lat)
	if !good {
		badBody(w)
		return
	}
	lonPresent, good := field(p, "lon", &lon)
	if !good {
		badBody(w)
		return
	}
	var tagsIn []string
	if present, good := field(p, "tags", &tagsIn); !good {
		badBody(w)
		return
	} else if present {
		norm, err := spots.NormalizeTags(r.Context(), h.repo.db, tagsIn)
		if errors.Is(err, tagset.ErrInvalid) {
			httpx.Error(w, http.StatusBadRequest, "invalid_tags", "tags must be distinct entries of the tag catalog (GET /tags)")
			return
		}
		if err != nil {
			serverError(w)
			return
		}
		sp.tags = &norm
	}
	var owner uint64
	if present, good := field(p, "owner_id", &owner); !good {
		badBody(w)
		return
	} else if present {
		sp.ownerID = &owner
	}
	var locked bool
	if present, good := field(p, "locked", &locked); !good {
		badBody(w)
		return
	} else if present {
		sp.locked = &locked
	}
	if sp.title != nil {
		t := strings.TrimSpace(*sp.title)
		sp.title = &t
		if n := utf8.RuneCountInString(t); n < 3 || n > 80 {
			httpx.Error(w, http.StatusBadRequest, "invalid_title", "title must be 3-80 characters")
			return
		}
	}
	if sp.description != nil && utf8.RuneCountInString(*sp.description) > 1000 {
		httpx.Error(w, http.StatusBadRequest, "invalid_description", "description must be at most 1000 characters")
		return
	}
	if sp.status != nil && *sp.status != "active" && *sp.status != "hidden" {
		httpx.Error(w, http.StatusBadRequest, "invalid_status", "status must be active or hidden")
		return
	}
	if latPresent != lonPresent {
		httpx.Error(w, http.StatusBadRequest, "invalid_location", "lat and lon must be sent together")
		return
	}
	if latPresent {
		if !spots.ValidCoord(lat, lon) || !spots.InRegion(lat, lon) {
			httpx.Error(w, http.StatusBadRequest, "invalid_location", "location must be valid and inside the supported region (DACH)")
			return
		}
		sp.lat, sp.lon = &lat, &lon
	}
	it, err := h.repo.patchSpot(r.Context(), id, sp)
	switch {
	case errors.Is(err, errNotFound):
		notFound(w, "spot")
	case errors.Is(err, errNoSuchOwner):
		httpx.Error(w, http.StatusBadRequest, "invalid_owner", "owner_id must be an existing user")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, it)
	}
}

func (r repo) patchSpot(ctx context.Context, id uint64, p spotPatch) (spotItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return spotItem{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	var one uint64
	err = tx.QueryRowContext(ctx, `SELECT id FROM spots WHERE id = ? FOR UPDATE`, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return spotItem{}, errNotFound
	}
	if err != nil {
		return spotItem{}, err
	}
	var sets []string
	var args []any
	for _, f := range []struct {
		col string
		v   *string
	}{{"title", p.title}, {"description", p.description}, {"status", p.status}} {
		if f.v != nil {
			sets, args = append(sets, f.col+" = ?"), append(args, *f.v)
		}
	}
	if p.ownerID != nil {
		var one uint64
		err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id = ?`, *p.ownerID).Scan(&one)
		if errors.Is(err, sql.ErrNoRows) {
			return spotItem{}, errNoSuchOwner
		}
		if err != nil {
			return spotItem{}, err
		}
		sets, args = append(sets, "user_id = ?"), append(args, *p.ownerID)
	}
	if p.locked != nil {
		sets, args = append(sets, "locked = ?"), append(args, *p.locked)
	}
	if p.lat != nil {
		// MariaDB POINT(x, y) = (lon, lat), as in the spots package.
		sets, args = append(sets, "location = POINT(?, ?)"), append(args, *p.lon, *p.lat)
	}
	if len(sets) > 0 {
		if _, err := tx.ExecContext(ctx, "UPDATE spots SET "+strings.Join(sets, ", ")+" WHERE id = ?", append(args, id)...); err != nil {
			return spotItem{}, err
		}
	}
	if p.tags != nil {
		if err := tagset.Replace(ctx, tx, id, *p.tags); err != nil {
			return spotItem{}, err
		}
	}
	it, err := scanSpot(tx.QueryRowContext(ctx, spotSelect+`WHERE s.id = ?`, id))
	if err != nil {
		return spotItem{}, err
	}
	tags, err := tagset.Load(ctx, tx, []uint64{id})
	if err != nil {
		return spotItem{}, err
	}
	if t := tags[id]; t != nil {
		it.Tags = t
	}
	return it, tx.Commit()
}

// ---- reports ----

func (h handler) deleteReport(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "report")
		return
	}
	res, err := h.repo.db.ExecContext(r.Context(), `DELETE FROM reports WHERE id = ?`, id)
	if err != nil {
		serverError(w)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		notFound(w, "report")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) dismiss(w http.ResponseWriter, r *http.Request) {
	var in struct {
		TargetType string `json:"target_type"`
		TargetID   int64  `json:"target_id"`
		Restore    bool   `json:"restore"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		badBody(w)
		return
	}
	if in.TargetType != "spot" && in.TargetType != "update" && in.TargetType != "review" {
		httpx.Error(w, http.StatusBadRequest, "invalid_target", "target_type must be spot, update or review")
		return
	}
	n, err := h.repo.dismiss(r.Context(), in.TargetType, in.TargetID, in.Restore)
	switch {
	case errors.Is(err, errNotFound):
		notFound(w, "target")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, map[string]int64{"removed": n})
	}
}

func (r repo) dismiss(ctx context.Context, typ string, id int64, restore bool) (int64, error) {
	table := "spots"
	switch typ {
	case "update":
		table = "spot_updates"
	case "review":
		table = "spot_reviews"
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback() //nolint:errcheck
	if restore {
		var one uint64
		err := tx.QueryRowContext(ctx, `SELECT id FROM `+table+` WHERE id = ? FOR UPDATE`, id).Scan(&one)
		if errors.Is(err, sql.ErrNoRows) {
			return 0, errNotFound
		}
		if err != nil {
			return 0, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE `+table+` SET status = 'active' WHERE id = ?`, id); err != nil {
			return 0, err
		}
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM reports WHERE target_type = ? AND target_id = ?`, typ, id)
	if err != nil {
		return 0, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}
	return n, tx.Commit()
}

// ---- review / update deletion ----

func (h handler) deleteReview(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "review")
		return
	}
	switch err := reviews.DeleteByID(r.Context(), h.repo.db, id); {
	case errors.Is(err, reviews.ErrNotFound):
		notFound(w, "review")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

func (h handler) deleteUpdate(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "update")
		return
	}
	switch err := feed.DeleteUpdateByID(r.Context(), h.repo.db, h.repo.uploadDir, id); {
	case errors.Is(err, feed.ErrUpdateNotFound):
		notFound(w, "update")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
