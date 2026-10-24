// Package tagset holds the canonical spot tag list and the SQL helpers shared
// by the spots, feed and admin packages. It is a separate package only because
// spots imports feed (and feed needs the tags); spots re-exports the API as
// spots.Tags, spots.ValidTag and spots.NormalizeTags.
package tagset

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

// Tags is the canonical tag list, in canonical order.
var Tags = []string{"roof", "seating", "view", "quiet", "shade", "water", "lit"}

// ErrInvalid is returned for unknown tags or more than len(Tags) entries.
var ErrInvalid = errors.New("invalid tags")

// Valid reports whether t is a known tag.
func Valid(t string) bool {
	for _, x := range Tags {
		if x == t {
			return true
		}
	}
	return false
}

// Normalize validates, dedupes and orders tags canonically. The result is never nil.
func Normalize(in []string) ([]string, error) {
	if len(in) > len(Tags) {
		return nil, ErrInvalid
	}
	have := map[string]bool{}
	for _, t := range in {
		if !Valid(t) {
			return nil, ErrInvalid
		}
		have[t] = true
	}
	out := make([]string, 0, len(have))
	for _, t := range Tags {
		if have[t] {
			out = append(out, t)
		}
	}
	return out, nil
}

// ParseParam parses a comma separated ?tags= value. Empty means no filter.
func ParseParam(s string) ([]string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	tags, err := Normalize(strings.Split(s, ","))
	if err != nil {
		return nil, err
	}
	return tags, nil
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
		"SELECT spot_id, tag FROM spot_tags WHERE spot_id IN ("+ph+") ORDER BY spot_id, FIELD(tag, 'roof','seating','view','quiet','shade','water','lit')", args...)
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
