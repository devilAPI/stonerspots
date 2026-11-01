package lists

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/go-sql-driver/mysql"

	"stonerspots/backend/internal/spots"
)

var (
	errListNotFound = errors.New("lists: list not found")
	errSpotNotFound = errors.New("lists: spot not found")
	errDefaultList  = errors.New("lists: default list is fixed")
	errNameTaken    = errors.New("lists: name taken")
	errListLimit    = errors.New("lists: too many lists")
	errNoUser       = errors.New("lists: user does not exist")
)

// defaultName is stored for API clients; the app translates it by is_default.
const defaultName = "Favourites"

// List is one of a user's lists. SpotCount and CoverURL only look at spots
// that are publicly visible.
type List struct {
	ID        uint64    `json:"id"`
	Name      string    `json:"name"`
	IsDefault bool      `json:"is_default"`
	SpotCount int       `json:"spot_count"`
	CoverURL  string    `json:"cover_url"`
	CreatedAt time.Time `json:"created_at"`
}

// selectList takes the media base URL and the owner as arguments. The cover
// is the first public photo of the most recently saved spot that has one.
const selectList = `SELECT l.id, l.name, l.is_default, l.created_at,
  (SELECT COUNT(*) FROM spot_list_items i JOIN spots s ON s.id = i.spot_id
    WHERE i.list_id = l.id AND s.status = 'active'),
  COALESCE((SELECT CONCAT(?, '/api/v1/media/', p.thumb_key)
    FROM spot_list_items i
    JOIN spots s ON s.id = i.spot_id
    JOIN spot_updates u ON u.spot_id = s.id
    JOIN photos p ON p.update_id = u.id
    WHERE i.list_id = l.id AND s.status = 'active' AND u.status = 'active' AND p.status = 'approved'
    ORDER BY i.id DESC, p.id LIMIT 1), '')
  FROM spot_lists l WHERE l.user_id = ?`

func scanList(row interface{ Scan(...any) error }) (List, error) {
	var l List
	err := row.Scan(&l.ID, &l.Name, &l.IsDefault, &l.CreatedAt, &l.SpotCount, &l.CoverURL)
	return l, err
}

type repo struct {
	db    *sql.DB
	base  string
	spots *spots.Repo
}

func nameErr(err error) error {
	var me *mysql.MySQLError
	if errors.As(err, &me) && me.Number == 1062 {
		return errNameTaken
	}
	return err
}

// defaultList returns the id of the user's default list, creating it if
// needed. Not in a transaction: the second read must see a row that a
// concurrent request has just committed.
func (r repo) defaultList(ctx context.Context, userID uint64) (uint64, error) {
	const find = `SELECT id FROM spot_lists WHERE user_id = ? AND is_default = 1`
	var id uint64
	err := r.db.QueryRowContext(ctx, find, userID).Scan(&id)
	if !errors.Is(err, sql.ErrNoRows) {
		return id, err
	}
	// IGNORE: the unique key settles races, and a user who is gone is no error
	if _, err := r.db.ExecContext(ctx,
		`INSERT IGNORE INTO spot_lists (user_id, name, is_default) VALUES (?, ?, 1)`, userID, defaultName); err != nil {
		return 0, err
	}
	err = r.db.QueryRowContext(ctx, find, userID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, errNoUser
	}
	return id, err
}

// all returns the user's lists, the default list first.
func (r repo) all(ctx context.Context, userID uint64) ([]List, error) {
	if _, err := r.defaultList(ctx, userID); err != nil {
		return nil, err
	}
	rows, err := r.db.QueryContext(ctx, selectList+` ORDER BY l.is_default DESC, l.name, l.id`, r.base, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []List{}
	for rows.Next() {
		l, err := scanList(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

func (r repo) get(ctx context.Context, userID, id uint64) (List, error) {
	l, err := scanList(r.db.QueryRowContext(ctx, selectList+` AND l.id = ?`, r.base, userID, id))
	if errors.Is(err, sql.ErrNoRows) {
		return l, errListNotFound
	}
	return l, err
}

// create adds a list. The user row is locked so that concurrent requests
// cannot pass the limit together.
func (r repo) create(ctx context.Context, userID uint64, name string) (List, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return List{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	var x uint64
	err = tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id = ? FOR UPDATE`, userID).Scan(&x)
	if errors.Is(err, sql.ErrNoRows) {
		return List{}, errNoUser
	}
	if err != nil {
		return List{}, err
	}
	var n int
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM spot_lists WHERE user_id = ? AND is_default = 0`, userID).Scan(&n); err != nil {
		return List{}, err
	}
	if n >= MaxLists {
		return List{}, errListLimit
	}
	res, err := tx.ExecContext(ctx, `INSERT INTO spot_lists (user_id, name) VALUES (?, ?)`, userID, name)
	if err != nil {
		return List{}, nameErr(err)
	}
	id, err := res.LastInsertId()
	if err != nil {
		return List{}, err
	}
	if err := tx.Commit(); err != nil {
		return List{}, err
	}
	return r.get(ctx, userID, uint64(id))
}

// ownEditable reports errListNotFound unless the list is the user's, and
// errDefaultList if it is the default list.
func (r repo) ownEditable(ctx context.Context, userID, id uint64) error {
	var isDefault bool
	err := r.db.QueryRowContext(ctx,
		`SELECT is_default FROM spot_lists WHERE id = ? AND user_id = ?`, id, userID).Scan(&isDefault)
	if errors.Is(err, sql.ErrNoRows) {
		return errListNotFound
	}
	if err != nil {
		return err
	}
	if isDefault {
		return errDefaultList
	}
	return nil
}

func (r repo) rename(ctx context.Context, userID, id uint64, name string) (List, error) {
	if _, err := r.db.ExecContext(ctx,
		`UPDATE spot_lists SET name = ? WHERE id = ? AND user_id = ? AND is_default = 0`, name, id, userID); err != nil {
		return List{}, nameErr(err)
	}
	return r.get(ctx, userID, id)
}

func (r repo) delete(ctx context.Context, userID, id uint64) error {
	if err := r.ownEditable(ctx, userID, id); err != nil {
		return err
	}
	_, err := r.db.ExecContext(ctx, `DELETE FROM spot_lists WHERE id = ? AND user_id = ? AND is_default = 0`, id, userID)
	return err
}

func (r repo) own(ctx context.Context, userID, id uint64) error {
	var x uint64
	err := r.db.QueryRowContext(ctx, `SELECT id FROM spot_lists WHERE id = ? AND user_id = ?`, id, userID).Scan(&x)
	if errors.Is(err, sql.ErrNoRows) {
		return errListNotFound
	}
	return err
}

// spotActive reports errSpotNotFound unless the spot is publicly visible.
func (r repo) spotActive(ctx context.Context, id uint64) error {
	var x uint64
	err := r.db.QueryRowContext(ctx, `SELECT id FROM spots WHERE id = ? AND status = 'active'`, id).Scan(&x)
	if errors.Is(err, sql.ErrNoRows) {
		return errSpotNotFound
	}
	return err
}

// add saves a spot; saving it again keeps its place in the list.
func (r repo) add(ctx context.Context, userID, id, spotID uint64) error {
	if err := r.own(ctx, userID, id); err != nil {
		return err
	}
	if err := r.spotActive(ctx, spotID); err != nil {
		return err
	}
	_, err := r.db.ExecContext(ctx, `INSERT IGNORE INTO spot_list_items (list_id, spot_id) VALUES (?, ?)`, id, spotID)
	return err
}

// remove takes a spot out, whatever its status: a hidden spot stays in the
// list, unseen, in case it comes back.
func (r repo) remove(ctx context.Context, userID, id, spotID uint64) error {
	if err := r.own(ctx, userID, id); err != nil {
		return err
	}
	_, err := r.db.ExecContext(ctx, `DELETE FROM spot_list_items WHERE list_id = ? AND spot_id = ?`, id, spotID)
	return err
}

// membership returns which of the user's lists hold the spot.
func (r repo) membership(ctx context.Context, userID, spotID uint64) ([]uint64, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT l.id FROM spot_lists l
		JOIN spot_list_items i ON i.list_id = l.id
		WHERE l.user_id = ? AND i.spot_id = ? ORDER BY l.id`, userID, spotID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []uint64{}
	for rows.Next() {
		var id uint64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// spotsIn returns a page of the list's visible spots, most recently saved
// first, and the cursor of the next page (0 at the end).
func (r repo) spotsIn(ctx context.Context, userID, id, cursor uint64, limit int) ([]spots.Spot, uint64, error) {
	if err := r.own(ctx, userID, id); err != nil {
		return nil, 0, err
	}
	q := `SELECT i.id, i.spot_id FROM spot_list_items i
		JOIN spot_lists l ON l.id = i.list_id
		JOIN spots s ON s.id = i.spot_id
		WHERE i.list_id = ? AND l.user_id = ? AND s.status = 'active'`
	args := []any{id, userID}
	if cursor != 0 {
		q += ` AND i.id < ?`
		args = append(args, cursor)
	}
	rows, err := r.db.QueryContext(ctx, q+` ORDER BY i.id DESC LIMIT ?`, append(args, limit+1)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	var itemIDs, spotIDs []uint64
	for rows.Next() {
		var itemID, spotID uint64
		if err := rows.Scan(&itemID, &spotID); err != nil {
			return nil, 0, err
		}
		itemIDs, spotIDs = append(itemIDs, itemID), append(spotIDs, spotID)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	rows.Close()
	var next uint64
	if len(spotIDs) > limit {
		spotIDs, next = spotIDs[:limit], itemIDs[limit-1]
	}
	list, err := r.spots.ByIDs(ctx, spotIDs)
	if err != nil {
		return nil, 0, err
	}
	return list, next, nil
}
