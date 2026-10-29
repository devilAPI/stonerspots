package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/mail"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"

	mailpkg "stonerspots/backend/internal/mail"
)

const (
	accessTTL  = 15 * time.Minute
	refreshTTL = 30 * 24 * time.Hour
	bcryptCost = 12
)

var (
	errEmailTaken     = errors.New("email taken")
	errNameTaken      = errors.New("display name taken")
	errBadCredentials = errors.New("invalid credentials")
	errBadRefresh     = errors.New("invalid refresh token")
	errBanned         = errors.New("account banned")
)

// User is the public user representation.
type User struct {
	ID          uint64 `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	IsAdmin     bool   `json:"is_admin"`

	banned bool // only read by refresh
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
	mail      *mailpkg.Client
}

// dummyHash is compared against when the email is unknown so that login
// timing does not reveal which emails exist.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("dummy-password"), bcryptCost)

func normalizeEmail(e string) string { return strings.ToLower(strings.TrimSpace(e)) }

// NormalizeEmail trims and lower-cases an email address.
func NormalizeEmail(e string) string { return normalizeEmail(e) }

// ValidEmail reports whether an already normalized email is acceptable
// (the registration rule).
func ValidEmail(email string) bool {
	a, err := mail.ParseAddress(email)
	return err == nil && a.Address == email && len(email) <= 255
}

// ValidDisplayName trims a display name and reports whether it is
// acceptable: 1 to 80 characters and no "@", since names double as login
// names and anything with an "@" is looked up as an email.
func ValidDisplayName(name string) (string, bool) {
	name = strings.TrimSpace(name)
	n := utf8.RuneCountInString(name)
	return name, n >= 1 && n <= 80 && !strings.Contains(name, "@")
}

// DuplicateUserField names the users column whose unique key err violates
// ("email" or "display_name"), or "" for any other error.
func DuplicateUserField(err error) string {
	var me *mysql.MySQLError
	if !errors.As(err, &me) || me.Number != 1062 {
		return ""
	}
	if strings.Contains(me.Message, "uq_users_display_name") {
		return "display_name"
	}
	return "email"
}

// byLogin is the WHERE clause and argument finding a user by what they
// typed to log in: an email when it has an "@", else their display name.
func byLogin(login string) (string, string) {
	if strings.Contains(login, "@") {
		return "email = ?", normalizeEmail(login)
	}
	return "display_name = ?", strings.TrimSpace(login)
}

// failureKey is the key wrong passwords are counted under: the account
// when it exists, so switching between email and name gains nothing.
func (s *service) failureKey(ctx context.Context, login string) string {
	where, arg := byLogin(login)
	var id uint64
	if err := s.db.QueryRowContext(ctx, `SELECT id FROM users WHERE `+where, arg).Scan(&id); err == nil {
		return "user:" + strconv.FormatUint(id, 10)
	}
	return "login:" + strings.ToLower(arg)
}

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

// generateToken returns a URL-safe random token for email verification.
func generateToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// sendVerificationEmail sends the verification email to the user.
func (s *service) sendVerificationEmail(ctx context.Context, email, token string) {
	verifyURL := "https://example.com/verify-email?token=" + token // TODO: use config.PublicBaseURL
	body := "Please verify your email address by clicking the following link:\n\n" +
		verifyURL + "\n\n" +
		"This link expires in 24 hours.\n\n" +
		"If you did not create an account, please ignore this email."
	_ = s.mail.Send(ctx, email, "Verify your Stonerspots account", body)
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
	// Generate email verification token if mail is enabled
	var verifyToken string
	var verifyExpires *time.Time
	if s.mail != nil && s.mail.Config().Enabled() {
		verifyToken = generateToken()
		expires := time.Now().UTC().Add(24 * time.Hour)
		verifyExpires = &expires
	}
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO users (email, password_hash, display_name, adult_confirmed_at, email_verify_token, email_verify_expires) VALUES (?, ?, ?, NOW(), ?, ?)`,
		email, string(hash), name, verifyToken, verifyExpires)
	if err != nil {
		var me *mysql.MySQLError
		if errors.As(err, &me) && me.Number == 1062 {
			if DuplicateUserField(err) == "display_name" {
				return nil, errNameTaken
			}
			return nil, errEmailTaken
		}
		return nil, err
	}
	id, _ := res.LastInsertId()
	user := User{ID: uint64(id), Email: email, DisplayName: name}
	// Send verification email if mail is enabled
	if s.mail != nil && s.mail.Config().Enabled() && verifyToken != "" {
		go s.sendVerificationEmail(context.Background(), email, verifyToken)
	}
	return s.session(ctx, user, "")
}

// login checks the password of the user named by login (email or display
// name, see byLogin).
func (s *service) login(ctx context.Context, login, password string) (*Session, error) {
	var u User
	var hash string
	var verified sql.NullBool
	var banned sql.NullTime
	where, arg := byLogin(login)
	err := s.db.QueryRowContext(ctx,
		`SELECT id, email, display_name, is_admin, password_hash, email_verified, banned_at FROM users WHERE `+where, arg,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.IsAdmin, &hash, &verified, &banned)
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
	// If mail is configured and email is not verified, reject login
	if s.mail != nil && s.mail.Config().Enabled() && !(verified.Valid && verified.Bool) {
		return nil, errBadCredentials
	}
	// only after the password: a wrong guess does not learn about the ban
	if banned.Valid {
		return nil, errBanned
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
	if u.banned {
		return nil, errBadRefresh
	}
	return s.session(ctx, *u, family)
}

// sendPasswordResetEmail sends the password reset email to the user.
func (s *service) sendPasswordResetEmail(ctx context.Context, email string) {
	var token string
	var expires *time.Time
	if s.mail != nil && s.mail.Config().Enabled() {
		token = generateToken()
		exp := time.Now().UTC().Add(1 * time.Hour)
		expires = &exp
		_, _ = s.db.ExecContext(ctx,
			`UPDATE users SET password_reset_token = ?, password_reset_expires = ? WHERE email = ?`, token, expires, email)
	}
	if token == "" {
		return
	}
	resetURL := "https://example.com/reset-password?token=" + token // TODO: use config.PublicBaseURL
	body := "Please reset your password by clicking the following link:\n\n" +
		resetURL + "\n\n" +
		"This link expires in 1 hour.\n\n" +
		"If you did not request a password reset, please ignore this email."
	_ = s.mail.Send(ctx, email, "Reset your Stonerspots password", body)
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
	var banned sql.NullTime
	err := s.db.QueryRowContext(ctx, `SELECT id, email, display_name, is_admin, banned_at FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.IsAdmin, &banned)
	if err != nil {
		return nil, err
	}
	u.banned = banned.Valid
	return &u, nil
}
