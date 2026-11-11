// Package dataexport answers GET /me/export: everything the database holds
// about the caller as one JSON download (right of access and data
// portability, Art. 15 and 20 GDPR). Secrets (password hash, 2FA secret,
// token hashes) are left out on purpose; the document says so.
package dataexport

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/ratelimit"
)

// Format names the layout of the document; bump it when fields change
// meaning.
const Format = "stonerspots-export/1"

// Filename is what the download is saved as.
const Filename = "stonerspots-export.json"

// Mount registers GET /me/export (login required, limited per user by
// limits.exports, 3 a day by default: the export reads every table).
func Mount(r chi.Router, d app.Deps) {
	perUser := ratelimit.Middleware(ratelimit.New(d.Cfg.Limits.Exports), func(r *http.Request) string {
		if id, ok := auth.UserID(r.Context()); ok {
			return "user:" + strconv.FormatUint(id, 10)
		}
		return ""
	})
	h := &handler{db: d.DB, base: d.Cfg.PublicBaseURL}
	r.With(auth.Middleware(d.Cfg.JWTSecret), perUser).Get("/me/export", h.export)
}

type handler struct {
	db   *sql.DB
	base string
}

func (h *handler) export(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.UserID(r.Context())
	doc, err := Build(r.Context(), h.db, h.base, id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
		return
	}
	if err != nil {
		log.Printf("export: user %d: %v", id, err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	body, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="`+Filename+`"`)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(append(body, '\n'))
}

// Document is the whole export.
type Document struct {
	Format     string    `json:"format"`
	ExportedAt time.Time `json:"exported_at"`
	Notes      []string  `json:"notes"`

	Profile  Profile   `json:"profile"`
	Spots    []Spot    `json:"spots"`
	Updates  []Update  `json:"updates"`
	Photos   []Photo   `json:"unattached_photos"`
	Comments []Comment `json:"comments"`
	Reviews  []Review  `json:"reviews"`
	Likes    []Like    `json:"likes"`

	Following []Follow `json:"following"`
	Followers []Follow `json:"followers"`

	Lists    []List     `json:"lists"`
	Reports  []Report   `json:"reports"`
	Activity []Activity `json:"activity"`
	Sessions []Session  `json:"sessions"`
}

var notes = []string{
	"Everything the Stonerspots server stores about your account, as of exported_at.",
	"Not included, for security: your password hash, your 2FA secret and the hashes of login, verification and reset tokens.",
	"Rate limits and daily quotas are kept only in the server's memory and are not stored.",
	"spot_title is null for spots that are hidden by moderation and not your own.",
}

type Profile struct {
	ID               uint64     `json:"id"`
	Email            string     `json:"email"`
	DisplayName      string     `json:"display_name"`
	Bio              string     `json:"bio"`
	CreatedAt        time.Time  `json:"created_at"`
	AdultConfirmedAt *time.Time `json:"adult_confirmed_at"`
	EmailVerified    bool       `json:"email_verified"`
	IsAdmin          bool       `json:"is_admin"`
	TOTPEnabled      bool       `json:"totp_enabled"`
	AvatarURL        *string    `json:"avatar_url"`
	BannedAt         *time.Time `json:"banned_at"`
}

type Spot struct {
	ID          uint64    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Lat         float64   `json:"lat"`
	Lon         float64   `json:"lon"`
	Status      string    `json:"status"`
	Locked      bool      `json:"locked"`
	LikeCount   int       `json:"like_count"`
	Tags        []string  `json:"tags"`
	CreatedAt   time.Time `json:"created_at"`
}

type Update struct {
	ID        uint64     `json:"id"`
	SpotID    uint64     `json:"spot_id"`
	SpotTitle *string    `json:"spot_title"`
	Body      string     `json:"body"`
	Tag       string     `json:"tag"`
	Status    string     `json:"status"`
	CreatedAt time.Time  `json:"created_at"`
	EditedAt  *time.Time `json:"edited_at"`
	Photos    []Photo    `json:"photos"`
}

type Photo struct {
	ID        uint64    `json:"id"`
	URL       string    `json:"url"`
	ThumbURL  string    `json:"thumb_url"`
	Width     int       `json:"width"`
	Height    int       `json:"height"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`

	updateID sql.NullInt64
}

type Comment struct {
	ID        uint64    `json:"id"`
	SpotID    uint64    `json:"spot_id"`
	SpotTitle *string   `json:"spot_title"`
	Body      string    `json:"body"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type Review struct {
	ID        uint64    `json:"id"`
	SpotID    uint64    `json:"spot_id"`
	SpotTitle *string   `json:"spot_title"`
	Rating    int       `json:"rating"`
	Body      string    `json:"body"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Like struct {
	SpotID    uint64    `json:"spot_id"`
	SpotTitle *string   `json:"spot_title"`
	CreatedAt time.Time `json:"created_at"`
}

// Follow is one follow relation: the other user and since when.
type Follow struct {
	UserID      uint64    `json:"user_id"`
	DisplayName string    `json:"display_name"`
	Since       time.Time `json:"since"`
}

type List struct {
	ID        uint64     `json:"id"`
	Name      string     `json:"name"`
	IsDefault bool       `json:"is_default"`
	CreatedAt time.Time  `json:"created_at"`
	Spots     []ListItem `json:"spots"`
}

type ListItem struct {
	SpotID    uint64    `json:"spot_id"`
	SpotTitle *string   `json:"spot_title"`
	AddedAt   time.Time `json:"added_at"`
}

type Report struct {
	ID         uint64    `json:"id"`
	TargetType string    `json:"target_type"`
	TargetID   uint64    `json:"target_id"`
	Reason     string    `json:"reason"`
	CreatedAt  time.Time `json:"created_at"`
}

// Activity is a notification addressed to the user.
type Activity struct {
	ID        uint64     `json:"id"`
	Kind      string     `json:"kind"`
	ActorID   uint64     `json:"actor_id"`
	ActorName string     `json:"actor_name"`
	SpotID    *uint64    `json:"spot_id"`
	UpdateID  *uint64    `json:"update_id"`
	CommentID *uint64    `json:"comment_id"`
	CreatedAt time.Time  `json:"created_at"`
	ReadAt    *time.Time `json:"read_at"`
}

// Session is one login (refresh token family member), without the token.
type Session struct {
	CreatedAt time.Time  `json:"created_at"`
	ExpiresAt time.Time  `json:"expires_at"`
	RevokedAt *time.Time `json:"revoked_at"`
}

// spotTitle is the title of spot s for user ?: hidden spots of others are
// left out (moderation removed them from view).
const spotTitle = `IF(s.status = 'active' OR s.user_id = ?, s.title, NULL)`

// Build collects the document for userID; sql.ErrNoRows for an unknown user.
// It reads in one read-only transaction, so the parts fit together.
func Build(ctx context.Context, db *sql.DB, publicBaseURL string, userID uint64) (*Document, error) {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback() //nolint:errcheck
	doc := &Document{Format: Format, ExportedAt: time.Now().UTC().Truncate(time.Second), Notes: notes}
	b := builder{tx: tx, ctx: ctx, base: publicBaseURL, uid: userID, doc: doc}
	for _, step := range []func() error{
		b.profile, b.spots, b.updates, b.comments, b.reviews, b.likes,
		b.follows, b.lists, b.reports, b.activity, b.sessions,
	} {
		if err := step(); err != nil {
			return nil, err
		}
	}
	return doc, nil
}

type builder struct {
	tx   *sql.Tx
	ctx  context.Context
	base string
	uid  uint64
	doc  *Document
}

// each runs query and calls scan for every row.
func (b *builder) each(query string, scan func(*sql.Rows) error, args ...any) error {
	rows, err := b.tx.QueryContext(b.ctx, query, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		if err := scan(rows); err != nil {
			return err
		}
	}
	return rows.Err()
}

func timePtr(t sql.NullTime) *time.Time {
	if !t.Valid {
		return nil
	}
	v := t.Time
	return &v
}

func idPtr(n sql.NullInt64) *uint64 {
	if !n.Valid {
		return nil
	}
	v := uint64(n.Int64)
	return &v
}

func strPtr(s sql.NullString) *string {
	if !s.Valid {
		return nil
	}
	v := s.String
	return &v
}

func (b *builder) profile() error {
	p := &b.doc.Profile
	var adult, banned sql.NullTime
	var avatar sql.NullString
	err := b.tx.QueryRowContext(b.ctx, `SELECT id, email, display_name, bio, created_at, adult_confirmed_at,
		email_verified, is_admin, totp_enabled, avatar_key, banned_at FROM users WHERE id = ?`, b.uid).
		Scan(&p.ID, &p.Email, &p.DisplayName, &p.Bio, &p.CreatedAt, &adult, &p.EmailVerified, &p.IsAdmin,
			&p.TOTPEnabled, &avatar, &banned)
	if err != nil {
		return err
	}
	p.AdultConfirmedAt = timePtr(adult)
	p.BannedAt = timePtr(banned)
	p.AvatarURL = app.AvatarURL(b.base, avatar)
	return nil
}

func (b *builder) spots() error {
	b.doc.Spots = []Spot{}
	index := map[uint64]int{}
	err := b.each(`SELECT id, title, description, ST_Y(location), ST_X(location), status, locked,
		like_count, created_at FROM spots WHERE user_id = ? ORDER BY id`, func(r *sql.Rows) error {
		s := Spot{Tags: []string{}}
		if err := r.Scan(&s.ID, &s.Title, &s.Description, &s.Lat, &s.Lon, &s.Status, &s.Locked,
			&s.LikeCount, &s.CreatedAt); err != nil {
			return err
		}
		index[s.ID] = len(b.doc.Spots)
		b.doc.Spots = append(b.doc.Spots, s)
		return nil
	}, b.uid)
	if err != nil {
		return err
	}
	return b.each(`SELECT t.spot_id, t.tag FROM spot_tags t JOIN spots s ON s.id = t.spot_id
		WHERE s.user_id = ? ORDER BY t.spot_id, t.tag`, func(r *sql.Rows) error {
		var id uint64
		var tag string
		if err := r.Scan(&id, &tag); err != nil {
			return err
		}
		if i, ok := index[id]; ok {
			b.doc.Spots[i].Tags = append(b.doc.Spots[i].Tags, tag)
		}
		return nil
	}, b.uid)
}

func (b *builder) updates() error {
	b.doc.Updates = []Update{}
	b.doc.Photos = []Photo{}
	index := map[uint64]int{}
	err := b.each(`SELECT u.id, u.spot_id, `+spotTitle+`, u.body, u.tag, u.status, u.created_at, u.edited_at
		FROM spot_updates u JOIN spots s ON s.id = u.spot_id WHERE u.user_id = ? ORDER BY u.id`,
		func(r *sql.Rows) error {
			u := Update{Photos: []Photo{}}
			var title sql.NullString
			var edited sql.NullTime
			if err := r.Scan(&u.ID, &u.SpotID, &title, &u.Body, &u.Tag, &u.Status, &u.CreatedAt, &edited); err != nil {
				return err
			}
			u.SpotTitle, u.EditedAt = strPtr(title), timePtr(edited)
			index[u.ID] = len(b.doc.Updates)
			b.doc.Updates = append(b.doc.Updates, u)
			return nil
		}, b.uid, b.uid)
	if err != nil {
		return err
	}
	// every photo the user uploaded: on their updates, or not attached yet
	return b.each("SELECT id, update_id, `key`, thumb_key, width, height, status, created_at FROM photos WHERE user_id = ? ORDER BY id",
		func(r *sql.Rows) error {
			var p Photo
			var key, thumb string
			if err := r.Scan(&p.ID, &p.updateID, &key, &thumb, &p.Width, &p.Height, &p.Status, &p.CreatedAt); err != nil {
				return err
			}
			p.URL, p.ThumbURL = app.MediaURL(b.base, key), app.MediaURL(b.base, thumb)
			if p.updateID.Valid {
				if i, ok := index[uint64(p.updateID.Int64)]; ok {
					b.doc.Updates[i].Photos = append(b.doc.Updates[i].Photos, p)
					return nil
				}
			}
			b.doc.Photos = append(b.doc.Photos, p)
			return nil
		}, b.uid)
}

func (b *builder) comments() error {
	b.doc.Comments = []Comment{}
	return b.each(`SELECT c.id, c.spot_id, `+spotTitle+`, c.body, c.status, c.created_at
		FROM comments c JOIN spots s ON s.id = c.spot_id WHERE c.user_id = ? ORDER BY c.id`,
		func(r *sql.Rows) error {
			var c Comment
			var title sql.NullString
			if err := r.Scan(&c.ID, &c.SpotID, &title, &c.Body, &c.Status, &c.CreatedAt); err != nil {
				return err
			}
			c.SpotTitle = strPtr(title)
			b.doc.Comments = append(b.doc.Comments, c)
			return nil
		}, b.uid, b.uid)
}

func (b *builder) reviews() error {
	b.doc.Reviews = []Review{}
	return b.each(`SELECT v.id, v.spot_id, `+spotTitle+`, v.rating, v.body, v.status, v.created_at, v.updated_at
		FROM spot_reviews v JOIN spots s ON s.id = v.spot_id WHERE v.user_id = ? ORDER BY v.id`,
		func(r *sql.Rows) error {
			var v Review
			var title sql.NullString
			if err := r.Scan(&v.ID, &v.SpotID, &title, &v.Rating, &v.Body, &v.Status, &v.CreatedAt, &v.UpdatedAt); err != nil {
				return err
			}
			v.SpotTitle = strPtr(title)
			b.doc.Reviews = append(b.doc.Reviews, v)
			return nil
		}, b.uid, b.uid)
}

func (b *builder) likes() error {
	b.doc.Likes = []Like{}
	return b.each(`SELECT l.spot_id, `+spotTitle+`, l.created_at
		FROM spot_likes l JOIN spots s ON s.id = l.spot_id WHERE l.user_id = ? ORDER BY l.created_at, l.spot_id`,
		func(r *sql.Rows) error {
			var l Like
			var title sql.NullString
			if err := r.Scan(&l.SpotID, &title, &l.CreatedAt); err != nil {
				return err
			}
			l.SpotTitle = strPtr(title)
			b.doc.Likes = append(b.doc.Likes, l)
			return nil
		}, b.uid, b.uid)
}

// follows lists both directions: whom the user follows and who follows
// them (the user sees the latter in their activity anyway). Only the
// public id and name of the others.
func (b *builder) follows() error {
	scan := func(into *[]Follow) func(*sql.Rows) error {
		return func(r *sql.Rows) error {
			var f Follow
			if err := r.Scan(&f.UserID, &f.DisplayName, &f.Since); err != nil {
				return err
			}
			*into = append(*into, f)
			return nil
		}
	}
	b.doc.Following, b.doc.Followers = []Follow{}, []Follow{}
	if err := b.each(`SELECT u.id, u.display_name, f.created_at FROM follows f
		JOIN users u ON u.id = f.followee_id WHERE f.follower_id = ? ORDER BY f.created_at, u.id`,
		scan(&b.doc.Following), b.uid); err != nil {
		return err
	}
	return b.each(`SELECT u.id, u.display_name, f.created_at FROM follows f
		JOIN users u ON u.id = f.follower_id WHERE f.followee_id = ? ORDER BY f.created_at, u.id`,
		scan(&b.doc.Followers), b.uid)
}

func (b *builder) lists() error {
	b.doc.Lists = []List{}
	index := map[uint64]int{}
	err := b.each(`SELECT id, name, is_default, created_at FROM spot_lists WHERE user_id = ? ORDER BY id`,
		func(r *sql.Rows) error {
			l := List{Spots: []ListItem{}}
			if err := r.Scan(&l.ID, &l.Name, &l.IsDefault, &l.CreatedAt); err != nil {
				return err
			}
			index[l.ID] = len(b.doc.Lists)
			b.doc.Lists = append(b.doc.Lists, l)
			return nil
		}, b.uid)
	if err != nil {
		return err
	}
	return b.each(`SELECT i.list_id, i.spot_id, `+spotTitle+`, i.created_at FROM spot_list_items i
		JOIN spot_lists l ON l.id = i.list_id JOIN spots s ON s.id = i.spot_id
		WHERE l.user_id = ? ORDER BY i.list_id, i.id`,
		func(r *sql.Rows) error {
			var listID uint64
			var it ListItem
			var title sql.NullString
			if err := r.Scan(&listID, &it.SpotID, &title, &it.AddedAt); err != nil {
				return err
			}
			it.SpotTitle = strPtr(title)
			if i, ok := index[listID]; ok {
				b.doc.Lists[i].Spots = append(b.doc.Lists[i].Spots, it)
			}
			return nil
		}, b.uid, b.uid)
}

func (b *builder) reports() error {
	b.doc.Reports = []Report{}
	return b.each(`SELECT id, target_type, target_id, reason, created_at FROM reports WHERE user_id = ? ORDER BY id`,
		func(r *sql.Rows) error {
			var p Report
			if err := r.Scan(&p.ID, &p.TargetType, &p.TargetID, &p.Reason, &p.CreatedAt); err != nil {
				return err
			}
			b.doc.Reports = append(b.doc.Reports, p)
			return nil
		}, b.uid)
}

func (b *builder) activity() error {
	b.doc.Activity = []Activity{}
	return b.each(`SELECT a.id, a.kind, a.actor_id, u.display_name, a.spot_id, a.update_id, a.comment_id,
		a.created_at, a.read_at FROM activity a JOIN users u ON u.id = a.actor_id
		WHERE a.user_id = ? ORDER BY a.id`,
		func(r *sql.Rows) error {
			var a Activity
			var spot, update, comment sql.NullInt64
			var read sql.NullTime
			if err := r.Scan(&a.ID, &a.Kind, &a.ActorID, &a.ActorName, &spot, &update, &comment, &a.CreatedAt, &read); err != nil {
				return err
			}
			a.SpotID, a.UpdateID, a.CommentID, a.ReadAt = idPtr(spot), idPtr(update), idPtr(comment), timePtr(read)
			b.doc.Activity = append(b.doc.Activity, a)
			return nil
		}, b.uid)
}

func (b *builder) sessions() error {
	b.doc.Sessions = []Session{}
	return b.each(`SELECT created_at, expires_at, revoked_at FROM refresh_tokens WHERE user_id = ? ORDER BY id`,
		func(r *sql.Rows) error {
			var s Session
			var revoked sql.NullTime
			if err := r.Scan(&s.CreatedAt, &s.ExpiresAt, &revoked); err != nil {
				return err
			}
			s.RevokedAt = timePtr(revoked)
			b.doc.Sessions = append(b.doc.Sessions, s)
			return nil
		}, b.uid)
}
