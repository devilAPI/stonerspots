package engagement

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

// Mount registers like and report routes on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := handler{repo: repo{db: d.DB}}
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Put("/spots/{id}/like", h.like(true))
	authed.Delete("/spots/{id}/like", h.like(false))
	authed.Post("/reports", h.report)
}

type handler struct{ repo repo }

func (h handler) like(liked bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := auth.UserID(r.Context())
		if !ok {
			httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
			return
		}
		id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
		if err != nil {
			httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
			return
		}
		count, err := h.repo.SetLike(r.Context(), uid, id, liked)
		if errors.Is(err, errNotFound) {
			httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
			return
		}
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "could not update like")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{"liked": liked, "like_count": count})
	}
}

func (h handler) report(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	var in struct {
		TargetType string `json:"target_type"`
		TargetID   uint64 `json:"target_id"`
		Reason     string `json:"reason"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_request", "invalid JSON body")
		return
	}
	if in.TargetType != "spot" && in.TargetType != "update" {
		httpx.Error(w, http.StatusBadRequest, "invalid_target", "target_type must be spot or update")
		return
	}
	if utf8.RuneCountInString(in.Reason) > 500 {
		httpx.Error(w, http.StatusBadRequest, "invalid_request", "reason too long (max 500)")
		return
	}
	created, err := h.repo.AddReport(r.Context(), uid, in.TargetType, in.TargetID, in.Reason)
	if errors.Is(err, errNotFound) {
		httpx.Error(w, http.StatusNotFound, "not_found", "target not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not save report")
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	httpx.JSON(w, status, map[string]any{"reported": true})
}
