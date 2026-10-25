// Package feed implements spot updates and the filterable feed.
package feed

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"stonerspots/backend/internal/spots/tagset"
)

var (
	// ErrInvalidPhoto: a photo is missing, not owned by the user, already attached,
	// duplicated, or there are more than MaxPhotos. Map to 400 invalid_photo.
	ErrInvalidPhoto = errors.New("feed: invalid photo")
	// ErrSpotNotFound: spot does not exist or is hidden. Map to 404.
	ErrSpotNotFound = errors.New("feed: spot not found")
	// ErrInvalidBody: body too long or update has neither text nor photos. Map to 400 invalid_body.
	ErrInvalidBody = errors.New("feed: invalid body")
	// ErrInvalidTag: tag is not one of Tags. Map to 400 invalid_tag.
	ErrInvalidTag = errors.New("feed: invalid tag")
	// ErrSpotLocked: the spot is locked and the user is no admin. Map to 403
	// spot_locked.
	ErrSpotLocked = errors.New("feed: spot locked")
)

// Tags are the allowed update tags.
var Tags = []string{"note", "still_good", "crowded", "dirty", "closed"}

// ValidTag reports whether t is an allowed update tag.
func ValidTag(t string) bool {
	for _, x := range Tags {
		if x == t {
			return true
		}
	}
	return false
}

const (
	MaxPhotos  = 4
	MaxBodyLen = 2000
)

type PhotoRef struct {
	ID       uint64 `json:"id"`
	URL      string `json:"url"`
	ThumbURL string `json:"thumb_url"`
}

type Author struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

type SpotRef struct {
	ID        uint64  `json:"id"`
	Title     string  `json:"title"`
	Lat       float64 `json:"lat"`
	Lon       float64 `json:"lon"`
	LikeCount int     `json:"like_count"`

	RatingAvg   float64  `json:"rating_avg"`
	RatingCount int      `json:"rating_count"`
	Tags        []string `json:"tags"`
}

type FeedItem struct {
	ID        uint64     `json:"id"`
	Body      string     `json:"body"`
	Photos    []PhotoRef `json:"photos"`
	CreatedAt time.Time  `json:"created_at"`
	Tag       string     `json:"tag"`
	EditedAt  *time.Time `json:"edited_at"`
	Author    Author     `json:"author"`
	Spot      SpotRef    `json:"spot"`

	// UpdateCount is how many active updates the spot has (>= 1): the feed
	// shows one card per spot, so older updates are reachable via this count.
	UpdateCount int `json:"update_count"`

	sortKey float64
}

// CreateUpdate inserts an update for spotID and atomically attaches photoIDs,
// which must belong to userID and be unattached. Returns the new update id.
func CreateUpdate(ctx context.Context, db *sql.DB, userID, spotID uint64, body string, photoIDs []uint64) (uint64, error) {
	return CreateUpdateTagged(ctx, db, userID, spotID, body, "note", photoIDs)
}

// CreateUpdateTagged is CreateUpdate with a tag (see ValidTag); "" means "note".
func CreateUpdateTagged(ctx context.Context, db *sql.DB, userID, spotID uint64, body, tag string, photoIDs []uint64) (uint64, error) {
	if tag == "" {
		tag = "note"
	}
	if !ValidTag(tag) {
		return 0, ErrInvalidTag
	}
	body = strings.TrimSpace(body)
	if len(body) > MaxBodyLen || (body == "" && len(photoIDs) == 0) {
		return 0, ErrInvalidBody
	}
	if len(photoIDs) > MaxPhotos {
		return 0, ErrInvalidPhoto
	}
	seen := map[uint64]bool{}
	for _, id := range photoIDs {
		if seen[id] {
			return 0, ErrInvalidPhoto
		}
		seen[id] = true
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	var locked, admin bool
	err = tx.QueryRowContext(ctx,
		"SELECT s.locked, COALESCE((SELECT is_admin FROM users WHERE id = ?), 0) FROM spots s WHERE s.id = ? AND s.status = 'active'",
		userID, spotID).Scan(&locked, &admin)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrSpotNotFound
	} else if err != nil {
		return 0, err
	}
	if locked && !admin {
		return 0, ErrSpotLocked
	}

	if len(photoIDs) > 0 {
		ph, args := placeholders(photoIDs)
		args = append(args, userID)
		rows, err := tx.QueryContext(ctx,
			"SELECT id FROM photos WHERE id IN ("+ph+") AND user_id = ? AND update_id IS NULL FOR UPDATE", args...)
		if err != nil {
			return 0, err
		}
		n := 0
		for rows.Next() {
			n++
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return 0, err
		}
		if n != len(photoIDs) {
			return 0, ErrInvalidPhoto
		}
	}

	res, err := tx.ExecContext(ctx, "INSERT INTO spot_updates (spot_id, user_id, body, tag) VALUES (?, ?, ?, ?)", spotID, userID, body, tag)
	if err != nil {
		return 0, err
	}
	lid, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	updateID := uint64(lid)

	if len(photoIDs) > 0 {
		ph, args := placeholders(photoIDs)
		args = append([]any{updateID}, args...)
		args = append(args, userID)
		r, err := tx.ExecContext(ctx,
			"UPDATE photos SET update_id = ? WHERE id IN ("+ph+") AND user_id = ? AND update_id IS NULL", args...)
		if err != nil {
			return 0, err
		}
		if n, _ := r.RowsAffected(); int(n) != len(photoIDs) {
			return 0, ErrInvalidPhoto
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return updateID, nil
}

func placeholders(ids []uint64) (string, []any) {
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	return strings.TrimSuffix(strings.Repeat("?,", len(ids)), ","), args
}

type sortMode string

const (
	sortNew    sortMode = "new"
	sortTop    sortMode = "top"
	sortNearby sortMode = "nearby"
)

type query struct {
	sort     sortMode
	tags     []string
	spotID   uint64
	lat, lon float64
	hasCur   bool
	curKey   float64
	curID    uint64
	limit    int
}

// The last selected column is always the sort key (see scanItem).
const selectBase = `SELECT u.id, u.body, u.created_at, u.tag, u.edited_at,
  a.id, a.display_name,
  s.id, s.title, ST_Y(s.location), ST_X(s.location), s.like_count,
  (SELECT COALESCE(ROUND(AVG(rv.rating), 1), 0) FROM spot_reviews rv WHERE rv.spot_id = s.id AND rv.status = 'active'),
  (SELECT COUNT(*) FROM spot_reviews rv WHERE rv.spot_id = s.id AND rv.status = 'active'),
  (SELECT COUNT(*) FROM spot_updates uc WHERE uc.spot_id = s.id AND uc.status = 'active')`

const fromBase = ` FROM spot_updates u
  JOIN spots s ON s.id = u.spot_id
  JOIN users a ON a.id = u.user_id`

const activeOnly = ` WHERE u.status = 'active' AND s.status = 'active'`

const distExpr = "ST_Distance_Sphere(s.location, POINT(?, ?))"

func scanItem(rows *sql.Rows) (FeedItem, error) {
	var it FeedItem
	err := rows.Scan(&it.ID, &it.Body, &it.CreatedAt, &it.Tag, &it.EditedAt,
		&it.Author.ID, &it.Author.DisplayName,
		&it.Spot.ID, &it.Spot.Title, &it.Spot.Lat, &it.Spot.Lon, &it.Spot.LikeCount,
		&it.Spot.RatingAvg, &it.Spot.RatingCount,
		&it.UpdateCount,
		&it.sortKey)
	it.Photos = []PhotoRef{}
	it.Spot.Tags = []string{}
	return it, err
}

// list returns up to q.limit items plus the next cursor (nil if none).
func list(ctx context.Context, db *sql.DB, base string, q query) ([]FeedItem, *string, error) {
	var keyCol, where, order string
	var keyArgs, curArgs, orderArgs []any
	switch q.sort {
	case sortTop:
		keyCol = "s.like_count"
		order = " ORDER BY s.like_count DESC, u.id DESC"
		if q.hasCur {
			where = " AND (s.like_count < ? OR (s.like_count = ? AND u.id < ?))"
			curArgs = []any{int64(q.curKey), int64(q.curKey), q.curID}
		}
	case sortNearby:
		keyCol = distExpr
		keyArgs = []any{q.lon, q.lat}
		order = " ORDER BY " + distExpr + " ASC, u.id ASC"
		orderArgs = []any{q.lon, q.lat}
		if q.hasCur {
			where = " AND (" + distExpr + " > ? OR (" + distExpr + " = ? AND u.id > ?))"
			curArgs = []any{q.lon, q.lat, q.curKey, q.lon, q.lat, q.curKey, q.curID}
		}
	default:
		keyCol = "UNIX_TIMESTAMP(u.created_at)"
		order = " ORDER BY u.created_at DESC, u.id DESC"
		if q.hasCur {
			where = " AND (u.created_at < FROM_UNIXTIME(?) OR (u.created_at = FROM_UNIXTIME(?) AND u.id < ?))"
			curArgs = []any{int64(q.curKey), int64(q.curKey), q.curID}
		}
	}
	var catWhere string
	var catArgs []any
	if q.spotID != 0 {
		// a spot's own timeline lists every update
		catWhere += " AND s.id = ?"
		catArgs = append(catArgs, q.spotID)
	} else {
		// the feed shows each spot once, with its latest active update
		catWhere += " AND u.id = (SELECT MAX(ul.id) FROM spot_updates ul WHERE ul.spot_id = u.spot_id AND ul.status = 'active')"
	}
	tq, targs := tagset.FilterSQL("s", q.tags)
	catWhere += tq
	catArgs = append(catArgs, targs...)
	// Placeholder order follows the SQL text: select, where(spot, tags, cursor), order, limit.
	args := append(append(append(append(keyArgs, catArgs...), curArgs...), orderArgs...), q.limit+1)

	rows, err := db.QueryContext(ctx, selectBase+", "+keyCol+fromBase+activeOnly+catWhere+where+order+" LIMIT ?", args...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	items := []FeedItem{}
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, nil, err
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	rows.Close()

	var next *string
	if len(items) > q.limit {
		items = items[:q.limit]
		last := items[len(items)-1]
		c := EncodeCursor(last.sortKey, last.ID)
		next = &c
	}
	if err := attachPhotos(ctx, db, base, items); err != nil {
		return nil, nil, err
	}
	if err := attachSpotTags(ctx, db, items); err != nil {
		return nil, nil, err
	}
	return items, next, nil
}

// attachSpotTags loads the tags of all items' spots with a single query.
func attachSpotTags(ctx context.Context, db *sql.DB, items []FeedItem) error {
	ids := make([]uint64, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.Spot.ID)
	}
	m, err := tagset.Load(ctx, db, ids)
	if err != nil {
		return err
	}
	for i := range items {
		if t := m[items[i].Spot.ID]; t != nil {
			items[i].Spot.Tags = t
		}
	}
	return nil
}

// attachPhotos loads the photos of all items with a single query.
func attachPhotos(ctx context.Context, db *sql.DB, base string, items []FeedItem) error {
	if len(items) == 0 {
		return nil
	}
	idx := map[uint64]int{}
	args := make([]any, 0, len(items))
	for i, it := range items {
		idx[it.ID] = i
		args = append(args, it.ID)
	}
	ph := strings.TrimSuffix(strings.Repeat("?,", len(args)), ",")
	rows, err := db.QueryContext(ctx,
		"SELECT id, update_id, `key`, thumb_key FROM photos WHERE update_id IN ("+ph+") ORDER BY id", args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var p PhotoRef
		var uid uint64
		var key, thumb string
		if err := rows.Scan(&p.ID, &uid, &key, &thumb); err != nil {
			return err
		}
		p.URL = base + "/api/v1/media/" + key
		p.ThumbURL = base + "/api/v1/media/" + thumb
		i := idx[uid]
		items[i].Photos = append(items[i].Photos, p)
	}
	return rows.Err()
}

// getItem loads one update as a FeedItem, or sql.ErrNoRows.
func getItem(ctx context.Context, db *sql.DB, base string, id uint64) (FeedItem, error) {
	rows, err := db.QueryContext(ctx, selectBase+", 0"+fromBase+" WHERE u.id = ?", id)
	if err != nil {
		return FeedItem{}, err
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return FeedItem{}, err
		}
		return FeedItem{}, sql.ErrNoRows
	}
	it, err := scanItem(rows)
	if err != nil {
		return FeedItem{}, err
	}
	rows.Close()
	items := []FeedItem{it}
	if err := attachPhotos(ctx, db, base, items); err != nil {
		return FeedItem{}, err
	}
	if err := attachSpotTags(ctx, db, items); err != nil {
		return FeedItem{}, err
	}
	return items[0], nil
}
