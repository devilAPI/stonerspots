package auth

import (
	"context"
	"net/http"
	"strings"

	"stonerspots/backend/internal/httpx"
)

type ctxKey struct{}

// UserID returns the authenticated user id from the request context.
func UserID(ctx context.Context) (uint64, bool) {
	id, ok := ctx.Value(ctxKey{}).(uint64)
	return id, ok
}

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const p = "Bearer "
	if len(h) > len(p) && strings.EqualFold(h[:len(p)], p) {
		return strings.TrimSpace(h[len(p):])
	}
	return ""
}

// Middleware requires a valid access token (401 `unauthorized` otherwise).
// When CheckAccount ran, tokens of deleted users get 401 `unauthorized` and
// those of banned users 401 `account_banned`.
func Middleware(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok := bearer(r)
			if tok == "" {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			id, err := parseAccess(secret, tok)
			if err != nil {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}
			if a, ok := loadedAccount(r.Context(), id); ok {
				switch {
				case a.missing:
					httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
					return
				case a.banned:
					httpx.Error(w, http.StatusUnauthorized, "account_banned", "this account is banned")
					return
				}
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, id)))
		})
	}
}

// Optional attaches the user id when a valid token is present and otherwise
// continues anonymously (never 401). Banned and deleted users (CheckAccount)
// are anonymous too.
func Optional(secret []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if tok := bearer(r); tok != "" {
				if id, err := parseAccess(secret, tok); err == nil && !dead(r.Context(), id) {
					r = r.WithContext(context.WithValue(r.Context(), ctxKey{}, id))
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// dead reports whether CheckAccount found user id banned or deleted.
func dead(ctx context.Context, id uint64) bool {
	a, ok := loadedAccount(ctx, id)
	return ok && (a.missing || a.banned)
}
