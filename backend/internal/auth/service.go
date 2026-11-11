package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"log"
	"net/mail"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/go-sql-driver/mysql"
	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/app"
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
	errNotVerified    = errors.New("email not verified")
)

// User is the public user representation.
type User struct {
	ID          uint64 `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	IsAdmin     bool   `json:"is_admin"`
	// AvatarURL is the profile picture, null when there is none.
	AvatarURL *string `json:"avatar_url"`

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
	base      string // public base URL, for avatar URLs
	appURL    string // where users open the app, for the links in mails
	mail      mailer
	// async runs mail jobs off the request (go f() when nil; tests make it
	// synchronous).
	async func(func())
}

// mailer is what the service needs from mail.Client.
type mailer interface {
	Enabled() bool
	Send(ctx context.Context, to, subject, body string) error
}

var _ mailer = (*mailpkg.Client)(nil)

// mailTimeout bounds one mail job (database update plus SMTP dialogue).
const mailTimeout = 30 * time.Second

func (s *service) mailOn() bool { return s.mail != nil && s.mail.Enabled() }

// background runs job with its own context: the request's context ends when
// the handler returns, which used to cancel the mail half way.
func (s *service) background(job func(ctx context.Context)) {
	run := func() {
		ctx, cancel := context.WithTimeout(context.Background(), mailTimeout)
		defer cancel()
		job(ctx)
	}
	if s.async != nil {
		s.async(run)
		return
	}
	go run()
}

// appLink is the app URL for path with the token as query parameter, e.g.
// https://devilapi.github.io/stonerspots/#/reset-password?token=...
func appLink(appURL, path, token string) string {
	return strings.TrimRight(appURL, "/") + path + "?token=" + url.QueryEscape(token)
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

// MaxBioLen and MaxBioLines bound a profile's bio.
const (
	MaxBioLen   = 300
	MaxBioLines = 6
)

// ValidBio tidies a bio: Windows line ends become \n, tabs spaces, other
// control characters go, spaces at line ends and the whole text's ends
// are trimmed, and more than one empty line in a row becomes one. ok is
// false when the result is longer than MaxBioLen characters or
// MaxBioLines lines. "" (no bio) is valid.
func ValidBio(bio string) (string, bool) {
	bio = strings.ReplaceAll(bio, "\r\n", "\n")
	bio = strings.ReplaceAll(bio, "\r", "\n")
	bio = strings.Map(func(r rune) rune {
		switch {
		case r == '\n':
			return r
		case r == '\t':
			return ' '
		case unicode.IsControl(r), r == '\u2028', r == '\u2029':
			return -1
		}
		return r
	}, bio)
	lines := strings.Split(bio, "\n")
	out := make([]string, 0, len(lines))
	for _, l := range lines {
		l = strings.TrimRightFunc(l, unicode.IsSpace)
		if l == "" && len(out) > 0 && out[len(out)-1] == "" {
			continue
		}
		out = append(out, l)
	}
	bio = strings.TrimSpace(strings.Join(out, "\n"))
	return bio, utf8.RuneCountInString(bio) <= MaxBioLen && strings.Count(bio, "\n") < MaxBioLines
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

// failureKey is the key wrong passwords are counted under: the account's
// id, so switching between email and name gains nothing. Unknown logins
// give "" and are not counted per account (the per-IP login limit still
// applies): counting them would let anyone fill the limiter's table with
// random names and so push out the counters of real accounts.
func (s *service) failureKey(ctx context.Context, login string) string {
	where, arg := byLogin(login)
	var id uint64
	if err := s.db.QueryRowContext(ctx, `SELECT id FROM users WHERE `+where, arg).Scan(&id); err == nil {
		return "user:" + strconv.FormatUint(id, 10)
	}
	return ""
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

// generateToken returns a URL-safe random token for email verification and
// password reset mails. Only its hashToken is stored.
func generateToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// sendVerificationEmail sends the verification email to the user.
func (s *service) sendVerificationEmail(ctx context.Context, email, token string) {
	verifyURL := appLink(s.appURL, "/verify-email", token)
	body := "Please verify your email address by clicking the following link:\n\n" +
		verifyURL + "\n\n" +
		"This link expires in 24 hours.\n\n" +
		"If you did not create an account, please ignore this email."
	if err := s.mail.Send(ctx, email, "Verify your Stonerspots account", body); err != nil {
		log.Printf("mail: verification mail not sent: %v", err)
	}
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
	var verifyHash *string
	var verifyExpires *time.Time
	if s.mailOn() {
		verifyToken = generateToken()
		h := hashToken(verifyToken)
		verifyHash = &h
		expires := time.Now().UTC().Add(24 * time.Hour)
		verifyExpires = &expires
	}
	res, err := s.db.ExecContext(ctx,
		`INSERT INTO users (email, password_hash, display_name, adult_confirmed_at, email_verify_hash, email_verify_expires) VALUES (?, ?, ?, NOW(), ?, ?)`,
		email, string(hash), name, verifyHash, verifyExpires)
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
	if verifyToken != "" {
		s.background(func(ctx context.Context) { s.sendVerificationEmail(ctx, email, verifyToken) })
	}
	return s.session(ctx, user, "")
}

// login checks the password of the user named by login (email or display
// name, see byLogin).
func (s *service) login(ctx context.Context, login, password string) (*Session, error) {
	var u User
	var hash string
	var verified sql.NullBool
	var pendingVerification bool
	var banned sql.NullTime
	var avatarKey sql.NullString
	where, arg := byLogin(login)
	err := s.db.QueryRowContext(ctx,
		`SELECT id, email, display_name, is_admin, avatar_key, password_hash, email_verified, email_verify_hash IS NOT NULL, banned_at FROM users WHERE `+where, arg,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.IsAdmin, &avatarKey, &hash, &verified, &pendingVerification, &banned)
	u.AvatarURL = app.AvatarURL(s.base, avatarKey)
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
	// With mail on, an account whose address still has to be verified
	// cannot log in. Accounts made while mail was off have nothing pending
	// and keep working; a password reset also verifies the address.
	if s.mailOn() && pendingVerification && !(verified.Valid && verified.Bool) {
		return nil, errNotVerified
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

// sendPasswordResetEmail stores a new reset token for the account with
// this email (if there is one and it is not banned) and mails the link. The
// caller answers the same either way, so nobody learns which emails exist.
func (s *service) sendPasswordResetEmail(ctx context.Context, email string) {
	if !s.mailOn() {
		return
	}
	token := generateToken()
	res, err := s.db.ExecContext(ctx,
		`UPDATE users SET password_reset_hash = ?, password_reset_expires = ? WHERE email = ? AND banned_at IS NULL`,
		hashToken(token), time.Now().UTC().Add(time.Hour), email)
	if err != nil {
		log.Printf("mail: reset token not stored: %v", err)
		return
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return // no such account: send nothing
	}
	resetURL := appLink(s.appURL, "/reset-password", token)
	body := "Please reset your password by clicking the following link:\n\n" +
		resetURL + "\n\n" +
		"This link expires in 1 hour.\n\n" +
		"If you did not request a password reset, please ignore this email."
	if err := s.mail.Send(ctx, email, "Reset your Stonerspots password", body); err != nil {
		log.Printf("mail: reset mail not sent: %v", err)
	}
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
	var avatarKey sql.NullString
	err := s.db.QueryRowContext(ctx, `SELECT id, email, display_name, is_admin, avatar_key, banned_at FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.IsAdmin, &avatarKey, &banned)
	if err != nil {
		return nil, err
	}
	u.banned = banned.Valid
	u.AvatarURL = app.AvatarURL(s.base, avatarKey)
	return &u, nil
}
