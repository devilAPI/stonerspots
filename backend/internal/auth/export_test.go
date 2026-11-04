package auth

import (
	"context"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/hibp"
)

// SentMail is one mail the FakeMailer got, with the state of the context it
// was sent under.
type SentMail struct {
	To, Subject, Body string
	CtxErr            error
	Deadline          time.Duration // until the context's deadline; 0: none
}

// FakeMailer records mails instead of sending them.
type FakeMailer struct {
	mu   sync.Mutex
	sent []SentMail
}

func (f *FakeMailer) Enabled() bool { return true }

func (f *FakeMailer) Send(ctx context.Context, to, subject, body string) error {
	m := SentMail{To: to, Subject: subject, Body: body, CtxErr: ctx.Err()}
	if d, ok := ctx.Deadline(); ok {
		m.Deadline = time.Until(d)
	}
	f.mu.Lock()
	f.sent = append(f.sent, m)
	f.mu.Unlock()
	return nil
}

// Sent returns the mails so far.
func (f *FakeMailer) Sent() []SentMail {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]SentMail(nil), f.sent...)
}

// Jobs collects the mail jobs the handlers start; Run runs them later, after
// the request (and its context) is gone.
type Jobs struct {
	mu   sync.Mutex
	jobs []func()
}

func (j *Jobs) add(f func()) {
	j.mu.Lock()
	j.jobs = append(j.jobs, f)
	j.mu.Unlock()
}

// Run runs and forgets the collected jobs.
func (j *Jobs) Run() {
	j.mu.Lock()
	jobs := j.jobs
	j.jobs = nil
	j.mu.Unlock()
	for _, f := range jobs {
		f()
	}
}

// MountWithFakeMail mounts the auth routes (without PoW) with mail going to
// m, mail jobs collected in jobs and HIBP asked at hibpURL ("" = real API).
func MountWithFakeMail(r chi.Router, d app.Deps, m *FakeMailer, jobs *Jobs, hibpURL string) {
	opts := MountOptions{DisablePoW: true, mailer: m, async: jobs.add}
	if hibpURL != "" {
		opts.hibp = hibp.NewClientAt(hibpURL)
	}
	MountWithOptions(r, d, opts)
}

// AppLink and DeriveKey expose the helpers to the tests.
var (
	AppLink   = appLink
	DeriveKey = deriveKey
)
