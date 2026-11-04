package admin

import (
	"errors"
	"net/http"

	"stonerspots/backend/internal/comments"
)

// deleteComment removes any comment (active or hidden) with its reports.
func (h handler) deleteComment(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "comment")
		return
	}
	switch err := comments.Delete(r.Context(), h.repo.db, id, 0); {
	case errors.Is(err, comments.ErrNotFound):
		notFound(w, "comment")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
