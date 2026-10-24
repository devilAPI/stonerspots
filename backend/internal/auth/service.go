package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"
)

const (
	accessTTL  = 15 * time.Minute
	refreshTTL = 30 * 24 * time.Hour
	bcryptCost = 12
)

var (
	errEmailTaken     = errors.New("email taken")
	errBadCredentials = errors.New("invalid credentials")
	errBadRefresh     = errors.New("invalid refresh token")
)

// User is the public user representation.
type User struct {
	ID          uint64 `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

// Session is returned by register, login and refresh.
type Session struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	User         User   `json:"user"`
}

type service struct {
	db        *sql.DB
	secret    []byte
	uploadDir string
}

// dummyHash is compared against when the email is unknown so that login
// timing does not reveal which emails exist.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("dummy-password"), bcryptCost)

func normalizeEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

func hashToken(tok string) string {
	sum := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(sum[:])
}

func newRefreshToken() (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b[:]), nil
}

func (s *service) session(ctx context.Context, u User, family string) (*Session, error) {
	access, err := IssueAccess(s.secret, u.ID, accessTTL)
	if err != nil {
		return nil, err
	}
	refresh, err := newRefreshToken()
	if err != nil {
		return nil, err
	}
	if family == "" {
		family = newUUID()
	}
	_, err = s.db.ExecContext(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at) VALUES (?, ?, ?, ?)`,
		u.ID, hashToken(refresh), family, time.Now().UTC().Add(refreshTTL))
	if err != nil {
		return nil, err
	}
	return &Session{AccessToken: access, RefreshToken: refresh, User: u}, nil
}

func (s *service) register(ctx context.Context, email, password, name string) (*Session, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return nil, err
	}
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO users (email, password_hash, display_name, adult_confirmed_at) VALUES (?, ?, ?, NOW())`, email, string(hash), name)
	if err != nil {
		var me *mysql.MySQLError
		if errors.As(err, &me) && me.Number == 1062 {
			return nil, errEmailTaken
		}
		return nil, err
	}
	id, _ := res.LastInsertId()
	return s.session(ctx, User{ID: uint64(id), Email: email, DisplayName: name}, "")
}

func (s *service) login(ctx context.Context, email, password string) (*Session, error) {
	var u User
	var hash string
	err := s.db.QueryRowContext(ctx,
		`SELECT id, email, display_name, password_hash FROM users WHERE email = ?`, email,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return nil, errBadCredentials
	}
	if err != nil {
		return nil, err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return nil, errBadCredentials
	}
	return s.session(ctx, u, "")
}

func (s *service) refresh(ctx context.Context, token string) (*Session, error) {
	var (
		id, userID uint64
		family     string
		expires    time.Time
		revoked    sql.NullTime
	)
	err := s.db.QueryRowContext(ctx,
		`SELECT id, user_id, family_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ?`,
		hashToken(token),
	).Scan(&id, &userID, &family, &expires, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, errBadRefresh
	}
	if err != nil {
		return nil, err
	}
	revokeFamily := func() {
		_, _ = s.db.ExecContext(ctx,
			`UPDATE refresh_tokens SET revoked_at = ? WHERE family_id = ? AND revoked_at IS NULL`,
			time.Now().UTC(), family)
	}
	if revoked.Valid {
		revokeFamily() // reuse of a rotated token: assume theft
		return nil, errBadRefresh
	}
	if time.Now().UTC().After(expires) {
		return nil, errBadRefresh
	}
	// Atomic claim; a concurrent second use loses and is treated as reuse.
	res, err := s.db.ExecContext(ctx,
		`UPDATE refresh_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL`, time.Now().UTC(), id)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		revokeFamily()
		return nil, errBadRefresh
	}
	u, err := s.user(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.session(ctx, *u, family)
}

// newUUID returns a random (v4) UUID string.
func newUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	h := hex.EncodeToString(b[:])
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

func (s *service) user(ctx context.Context, id uint64) (*User, error) {
	var u User
	err := s.db.QueryRowContext(ctx, `SELECT id, email, display_name FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Email, &u.DisplayName)
	if err != nil {
		return nil, err
	}
	return &u, nil
}
