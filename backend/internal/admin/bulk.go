package admin

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"slices"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/spots/tagset"
)

// maxBulk is the most ids one bulk request may name.
const maxBulk = 200

// skipped is an id a bulk action left alone, and why.
type skipped struct {
	ID     uint64 `json:"id"`
	Reason string `json:"reason"` // not_found, self, admin
}

// bulkResult answers a bulk request: the changed rows as they are now, the
// deleted ids and the skipped ones.
type bulkResult[T any] struct {
	Items   []T       `json:"items"`
	Deleted []uint64  `json:"deleted"`
	Skipped []skipped `json:"skipped"`
}

func newBulkResult[T any]() bulkResult[T] {
	return bulkResult[T]{Items: []T{}, Deleted: []uint64{}, Skipped: []skipped{}}
}

type bulkRequest struct {
	IDs    []uint64 `json:"ids"`
	Action string   `json:"action"`
	Tag    string   `json:"tag"`
}

func readBulk(w http.ResponseWriter, r *http.Request, actions ...string) (bulkRequest, bool) {
	var in bulkRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		badBody(w)
		return in, false
	}
	if !slices.Contains(actions, in.Action) {
		httpx.Error(w, http.StatusBadRequest, "invalid_action", "unknown bulk action")
		return in, false
	}
	if len(in.IDs) == 0 || len(in.IDs) > maxBulk {
		httpx.Error(w, http.StatusBadRequest, "invalid_ids", "ids must name 1 to 200 items")
		return in, false
	}
	slices.Sort(in.IDs)
	in.IDs = slices.Compact(in.IDs)
	return in, true
}

// bulkUsers bans, unbans or deletes users. The caller and other admins are
// skipped: an admin has to be demoted first.
func (h handler) bulkUsers(w http.ResponseWriter, r *http.Request) {
	in, ok := readBulk(w, r, "ban", "unban", "delete")
	if !ok {
		return
	}
	caller, _ := auth.UserID(r.Context())
	ctx := r.Context()
	out := newBulkResult[userItem]()
	for _, id := range in.IDs {
		var isAdmin bool
		err := h.repo.db.QueryRowContext(ctx, `SELECT is_admin FROM users WHERE id = ?`, id).Scan(&isAdmin)
		switch {
		case errors.Is(err, sql.ErrNoRows):
			out.Skipped = append(out.Skipped, skipped{id, "not_found"})
			continue
		case err != nil:
			serverError(w)
			return
		case id == caller:
			out.Skipped = append(out.Skipped, skipped{id, "self"})
			continue
		case isAdmin:
			out.Skipped = append(out.Skipped, skipped{id, "admin"})
			continue
		}
		if in.Action == "delete" {
			switch err := auth.DeleteUser(ctx, h.repo.db, h.repo.uploadDir, id); {
			case errors.Is(err, auth.ErrNoUser):
				out.Skipped = append(out.Skipped, skipped{id, "not_found"})
			case err != nil:
				serverError(w)
				return
			default:
				out.Deleted = append(out.Deleted, id)
			}
			continue
		}
		it, err := h.repo.setBanned(ctx, id, in.Action == "ban")
		if err != nil {
			serverError(w)
			return
		}
		out.Items = append(out.Items, it)
	}
	httpx.JSON(w, http.StatusOK, out)
}

// setBanned bans (ending every session) or unbans a user.
func (r repo) setBanned(ctx context.Context, id uint64, ban bool) (userItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return userItem{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	if ban {
		// keeps the first ban's time when banned again
		if _, err := tx.ExecContext(ctx, `UPDATE users SET banned_at = COALESCE(banned_at, UTC_TIMESTAMP()) WHERE id = ?`, id); err != nil {
			return userItem{}, err
		}
		// no new access tokens; the current one runs out within minutes
		if _, err := tx.ExecContext(ctx, `UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP() WHERE user_id = ? AND revoked_at IS NULL`, id); err != nil {
			return userItem{}, err
		}
	} else if _, err := tx.ExecContext(ctx, `UPDATE users SET banned_at = NULL WHERE id = ?`, id); err != nil {
		return userItem{}, err
	}
	it, err := scanUser(tx.QueryRowContext(ctx, userSelect+`WHERE u.id = ?`, id))
	if err != nil {
		return userItem{}, err
	}
	return it, tx.Commit()
}

// bulkSpots hides, shows, locks, unlocks, tags, untags or deletes spots.
func (h handler) bulkSpots(w http.ResponseWriter, r *http.Request) {
	in, ok := readBulk(w, r, "hide", "show", "lock", "unlock", "add_tag", "remove_tag", "delete")
	if !ok {
		return
	}
	ctx := r.Context()
	tagged := in.Action == "add_tag" || in.Action == "remove_tag"
	if tagged {
		if _, err := tagset.Normalize(ctx, h.repo.db, []string{in.Tag}); errors.Is(err, tagset.ErrInvalid) {
			httpx.Error(w, http.StatusBadRequest, "invalid_tags", "tag must be an entry of the tag catalog (GET /tags)")
			return
		} else if err != nil {
			serverError(w)
			return
		}
	}
	out := newBulkResult[spotItem]()
	for _, id := range in.IDs {
		var err error
		if in.Action == "delete" {
			if err = h.repo.deleteSpot(ctx, id); err == nil {
				out.Deleted = append(out.Deleted, id)
			}
		} else {
			var p spotPatch
			p, err = h.repo.bulkSpotPatch(ctx, id, in.Action, in.Tag)
			var it spotItem
			if err == nil {
				it, err = h.repo.patchSpot(ctx, id, p)
			}
			if err == nil {
				out.Items = append(out.Items, it)
			}
		}
		switch {
		case errors.Is(err, errNotFound):
			out.Skipped = append(out.Skipped, skipped{id, "not_found"})
		case err != nil:
			serverError(w)
			return
		}
	}
	httpx.JSON(w, http.StatusOK, out)
}

// bulkSpotPatch is the change one bulk action makes to spot id.
func (r repo) bulkSpotPatch(ctx context.Context, id uint64, action, tag string) (spotPatch, error) {
	var p spotPatch
	str := func(s string) *string { return &s }
	flag := func(b bool) *bool { return &b }
	switch action {
	case "hide":
		p.status = str("hidden")
	case "show":
		p.status = str("active")
	case "lock":
		p.locked = flag(true)
	case "unlock":
		p.locked = flag(false)
	case "add_tag", "remove_tag":
		all, err := tagset.Load(ctx, r.db, []uint64{id})
		if err != nil {
			return p, err
		}
		tags := slices.DeleteFunc(slices.Clone(all[id]), func(t string) bool { return t == tag })
		if action == "add_tag" {
			tags = append(tags, tag)
		}
		norm, err := tagset.Normalize(ctx, r.db, tags)
		if err != nil {
			return p, err
		}
		p.tags = &norm
	}
	return p, nil
}
