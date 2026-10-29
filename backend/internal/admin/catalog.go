package admin

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/go-sql-driver/mysql"

	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/spots/tagset"
)

// ---- updates ----

func (h handler) patchUpdate(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "update")
		return
	}
	p, ok := readPatch(w, r, "body", "tag", "status", "owner_id")
	if !ok {
		return
	}
	var owner *uint64
	var o uint64
	if present, good := field(p, "owner_id", &o); !good {
		badBody(w)
		return
	} else if present {
		owner = &o
	}
	var body, tag, status *string
	for key, dst := range map[string]**string{"body": &body, "tag": &tag, "status": &status} {
		var v string
		present, good := field(p, key, &v)
		if !good {
			badBody(w)
			return
		}
		if present {
			*dst = &v
		}
	}
	switch err := feed.AdminEditUpdate(r.Context(), h.repo.db, id, body, tag, status, owner); {
	case errors.Is(err, feed.ErrUpdateNotFound):
		notFound(w, "update")
	case errors.Is(err, feed.ErrInvalidTag):
		httpx.Error(w, http.StatusBadRequest, "invalid_tag", "tag must be one of note, still_good, crowded, dirty, closed")
	case errors.Is(err, feed.ErrInvalidStatus):
		httpx.Error(w, http.StatusBadRequest, "invalid_status", "status must be active or hidden")
	case errors.Is(err, feed.ErrInvalidBody):
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "body must be at most 2000 characters; text or photos required")
	case errors.Is(err, feed.ErrNoSuchOwner):
		httpx.Error(w, http.StatusBadRequest, "invalid_owner", "owner_id must be an existing user")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// ---- tag catalog ----

var (
	tagKeyRe  = regexp.MustCompile(`^[a-z][a-z0-9_]{1,15}$`)
	tagIconRe = regexp.MustCompile(`^[a-z0-9_]{1,32}$`)

	errTagTaken = errors.New("tag taken")
)

// catalogTag is a catalog entry with the number of spots using it.
type catalogTag struct {
	tagset.Tag
	SpotCount int `json:"spot_count"`
}

func (h handler) listTags(w http.ResponseWriter, r *http.Request) {
	rows, err := h.repo.db.QueryContext(r.Context(), `SELECT t.tag, t.name_de, t.name_en, t.icon, t.sort,
			(SELECT COUNT(*) FROM spot_tags st WHERE st.tag = t.tag)
		FROM tags t ORDER BY t.sort, t.tag`)
	if err != nil {
		serverError(w)
		return
	}
	defer rows.Close()
	out := []catalogTag{}
	for rows.Next() {
		var c catalogTag
		if err := rows.Scan(&c.Tag.Tag, &c.NameDE, &c.NameEN, &c.Icon, &c.Sort, &c.SpotCount); err != nil {
			serverError(w)
			return
		}
		out = append(out, c)
	}
	if rows.Err() != nil {
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

// tagFields validates the editable fields present in p into t; it writes
// the 400 itself.
func tagFields(w http.ResponseWriter, p map[string]json.RawMessage, t *tagset.Tag) bool {
	for key, dst := range map[string]*string{"name_de": &t.NameDE, "name_en": &t.NameEN} {
		var v string
		present, good := field(p, key, &v)
		if !good {
			badBody(w)
			return false
		}
		if !present {
			continue
		}
		v = strings.TrimSpace(v)
		if n := utf8.RuneCountInString(v); n < 1 || n > 40 {
			httpx.Error(w, http.StatusBadRequest, "invalid_name", key+" must be 1 to 40 characters")
			return false
		}
		*dst = v
	}
	var icon string
	if present, good := field(p, "icon", &icon); !good {
		badBody(w)
		return false
	} else if present {
		if !tagIconRe.MatchString(icon) {
			httpx.Error(w, http.StatusBadRequest, "invalid_icon", "icon must be 1 to 32 of a-z, 0-9 and _")
			return false
		}
		t.Icon = icon
	}
	if _, good := field(p, "sort", &t.Sort); !good {
		badBody(w)
		return false
	}
	return true
}

func (h handler) createTag(w http.ResponseWriter, r *http.Request) {
	p, ok := readPatch(w, r, "tag", "name_de", "name_en", "icon", "sort")
	if !ok {
		return
	}
	var t tagset.Tag
	if present, good := field(p, "tag", &t.Tag); !good {
		badBody(w)
		return
	} else if !present || !tagKeyRe.MatchString(t.Tag) {
		httpx.Error(w, http.StatusBadRequest, "invalid_tag", "tag must be 2 to 16 of a-z, 0-9 and _, starting with a letter")
		return
	}
	_, sortGiven := p["sort"]
	if !tagFields(w, p, &t) {
		return
	}
	if t.NameDE == "" || t.NameEN == "" || t.Icon == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_field", "tag, name_de, name_en and icon are required")
		return
	}
	switch err := h.repo.createTag(r.Context(), &t, sortGiven); {
	case errors.Is(err, errTagTaken):
		httpx.Error(w, http.StatusConflict, "tag_taken", "a tag with this key already exists")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusCreated, t)
	}
}

func (r repo) createTag(ctx context.Context, t *tagset.Tag, sortGiven bool) error {
	if !sortGiven {
		// new tags go to the end
		if err := r.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(sort), 0) + 10 FROM tags`).Scan(&t.Sort); err != nil {
			return err
		}
	}
	_, err := r.db.ExecContext(ctx, `INSERT INTO tags (tag, name_de, name_en, icon, sort) VALUES (?, ?, ?, ?, ?)`,
		t.Tag, t.NameDE, t.NameEN, t.Icon, t.Sort)
	var me *mysql.MySQLError
	if errors.As(err, &me) && me.Number == 1062 {
		return errTagTaken
	}
	return err
}

func (h handler) patchTag(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "tag")
	p, ok := readPatch(w, r, "name_de", "name_en", "icon", "sort")
	if !ok {
		return
	}
	ctx := r.Context()
	var t tagset.Tag
	err := h.repo.db.QueryRowContext(ctx, `SELECT tag, name_de, name_en, icon, sort FROM tags WHERE tag = ?`, key).
		Scan(&t.Tag, &t.NameDE, &t.NameEN, &t.Icon, &t.Sort)
	if errors.Is(err, sql.ErrNoRows) {
		notFound(w, "tag")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	if !tagFields(w, p, &t) {
		return
	}
	if _, err := h.repo.db.ExecContext(ctx, `UPDATE tags SET name_de = ?, name_en = ?, icon = ?, sort = ? WHERE tag = ?`,
		t.NameDE, t.NameEN, t.Icon, t.Sort, key); err != nil {
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusOK, t)
}

// deleteTag removes a tag from the catalog and (by foreign key) from every
// spot that had it.
func (h handler) deleteTag(w http.ResponseWriter, r *http.Request) {
	res, err := h.repo.db.ExecContext(r.Context(), `DELETE FROM tags WHERE tag = ?`, chi.URLParam(r, "tag"))
	if err != nil {
		serverError(w)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		notFound(w, "tag")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
