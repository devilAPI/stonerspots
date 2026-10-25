// Package tagset holds the spot tag catalog (table tags) and the SQL helpers
// shared by the spots, feed and admin packages. It is a separate package only
// because spots imports feed (and feed needs the tags).
package tagset

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

// Tag is one entry of the tag catalog (table tags), which admins manage.
type Tag struct {
	Tag    string `json:"tag"`
	NameDE string `json:"name_de"`
	NameEN string `json:"name_en"`
	Icon   string `json:"icon"`
	Sort   int    `json:"sort"`
}

// ErrInvalid is returned for unknown tags or more entries than tags exist.
var ErrInvalid = errors.New("invalid tags")

// orderSQL sorts spot_tags rows (alias st) in catalog order.
const orderSQL = "(SELECT t.sort FROM tags t WHERE t.tag = st.tag), st.tag"

// List returns the tag catalog in canonical order.
func List(ctx context.Context, q Querier) ([]Tag, error) {
	rows, err := q.QueryContext(ctx, "SELECT tag, name_de, name_en, icon, sort FROM tags ORDER BY sort, tag")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Tag{}
	for rows.Next() {
		var t Tag
		if err := rows.Scan(&t.Tag, &t.NameDE, &t.NameEN, &t.Icon, &t.Sort); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// Keys returns the catalog's tag keys in canonical order.
func Keys(ctx context.Context, q Querier) ([]string, error) {
	all, err := List(ctx, q)
	if err != nil {
		return nil, err
	}
	keys := make([]string, len(all))
	for i, t := range all {
		keys[i] = t.Tag
	}
	return keys, nil
}

// Normalize validates against the catalog, dedupes and orders tags
// canonically. The result is never nil.
func Normalize(ctx context.Context, q Querier, in []string) ([]string, error) {
	keys, err := Keys(ctx, q)
	if err != nil {
		return nil, err
	}
	return normalize(keys, in)
}

func normalize(keys, in []string) ([]string, error) {
	if len(in) > len(keys) {
		return nil, ErrInvalid
	}
	known := map[string]bool{}
	for _, k := range keys {
		known[k] = true
	}
	have := map[string]bool{}
	for _, t := range in {
		if !known[t] {
			return nil, ErrInvalid
		}
		have[t] = true
	}
	out := make([]string, 0, len(have))
	for _, k := range keys {
		if have[k] {
			out = append(out, k)
		}
	}
	return out, nil
}

// ParseParam parses a comma separated ?tags= value. Empty means no filter.
func ParseParam(ctx context.Context, q Querier, s string) ([]string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	return Normalize(ctx, q, strings.Split(s, ","))
}

// FilterSQL returns one EXISTS clause per tag (AND semantics), each starting
// with " AND ", for a query whose spots table alias is alias. The "= 1"
// keeps MariaDB from flattening the EXISTS into a semijoin, which could make it
// drive the query from spot_tags (temporary table + filesort) instead of the
// spatial index; as plain subqueries they are primary-key lookups per candidate.
func FilterSQL(alias string, tags []string) (string, []any) {
	var b strings.Builder
	args := make([]any, 0, len(tags))
	for _, t := range tags {
		b.WriteString(" AND EXISTS (SELECT 1 FROM spot_tags st WHERE st.spot_id = " + alias + ".id AND st.tag = ?) = 1")
		args = append(args, t)
	}
	return b.String(), args
}

// Querier is satisfied by *sql.DB and *sql.Tx.
type Querier interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// Load returns the tags of all given spots with ONE query, in canonical order.
// Spots without tags are absent from the map.
func Load(ctx context.Context, q Querier, ids []uint64) (map[uint64][]string, error) {
	out := map[uint64][]string{}
	if len(ids) == 0 {
		return out, nil
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	ph := strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",")
	rows, err := q.QueryContext(ctx,
		"SELECT st.spot_id, st.tag FROM spot_tags st WHERE st.spot_id IN ("+ph+") ORDER BY st.spot_id, "+orderSQL, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id uint64
		var tag string
		if err := rows.Scan(&id, &tag); err != nil {
			return nil, err
		}
		out[id] = append(out[id], tag)
	}
	return out, rows.Err()
}

// Replace sets the tag set of a spot to tags (already normalized).
func Replace(ctx context.Context, q Querier, spotID uint64, tags []string) error {
	if _, err := q.ExecContext(ctx, "DELETE FROM spot_tags WHERE spot_id = ?", spotID); err != nil {
		return err
	}
	if len(tags) == 0 {
		return nil
	}
	args := make([]any, 0, len(tags)*2)
	for _, t := range tags {
		args = append(args, spotID, t)
	}
	_, err := q.ExecContext(ctx,
		"INSERT INTO spot_tags (spot_id, tag) VALUES "+strings.TrimSuffix(strings.Repeat("(?, ?),", len(tags)), ","), args...)
	return err
}
