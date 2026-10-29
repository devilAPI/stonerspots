package admin_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

type sysOut struct {
	Version        string `json:"version"`
	UpdatesEnabled bool   `json:"updates_enabled"`
	Update         struct {
		State      string  `json:"state"`
		Channel    string  `json:"channel"`
		From       string  `json:"from"`
		To         string  `json:"to"`
		StartedAt  *string `json:"started_at"`
		FinishedAt *string `json:"finished_at"`
		Log        string  `json:"log"`
	} `json:"update"`
}

func TestSystemUpdatesOffWithoutUpdateDir(t *testing.T) {
	e := setup(t)
	var out sysOut
	decode(t, e.do(t, "GET", "/admin/system", e.tok), &out)
	if out.UpdatesEnabled || out.Update.State != "idle" {
		t.Fatalf("%+v", out)
	}
	e.expect(t, e.send(t, "POST", "/admin/system/update", e.tok, `{"channel":"dev"}`), 503, "updates_disabled")
}

func TestSystemUpdateRequest(t *testing.T) {
	dir := t.TempDir()
	for _, d := range []string{"request", "status"} {
		if err := os.Mkdir(filepath.Join(dir, d), 0o750); err != nil {
			t.Fatal(err)
		}
	}
	e := setupWith(t, func(c *config.Config) { c.UpdateDir = dir })
	user := testutil.NewUser(t, e.db)
	e.expect(t, e.do(t, "GET", "/admin/system", testutil.Token(t, user)), 403, "")
	e.expect(t, e.send(t, "POST", "/admin/system/update", e.tok, `{"channel":"main; rm -rf /"}`), 400, "invalid_channel")

	w := e.send(t, "POST", "/admin/system/update", e.tok, `{"channel":"dev"}`)
	e.expect(t, w, 202, "")
	var out sysOut
	decode(t, w, &out)
	if !out.UpdatesEnabled || out.Update.State != "pending" {
		t.Fatalf("%+v", out)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "request", "channel")); string(b) != "dev\n" {
		t.Fatalf("request file: %q", b)
	}
	// one at a time
	e.expect(t, e.send(t, "POST", "/admin/system/update", e.tok, `{"channel":"release"}`), 409, "update_in_progress")

	// what the root runner reports
	os.Remove(filepath.Join(dir, "request", "channel"))
	state := "state=failed\nchannel=dev\nfrom=dev-1\nto=dev-2\nstarted=2026-10-29T10:00:00Z\nfinished=2026-10-29T10:01:00+01:00\n"
	if err := os.WriteFile(filepath.Join(dir, "status", "state"), []byte(state), 0o640); err != nil {
		t.Fatal(err)
	}
	log := strings.Repeat("old line\n", 2000) + "==> did not start\n"
	if err := os.WriteFile(filepath.Join(dir, "status", "log"), []byte(log), 0o640); err != nil {
		t.Fatal(err)
	}
	decode(t, e.do(t, "GET", "/admin/system", e.tok), &out)
	u := out.Update
	if u.State != "failed" || u.Channel != "dev" || u.From != "dev-1" || u.To != "dev-2" ||
		u.StartedAt == nil || *u.FinishedAt != "2026-10-29T09:01:00Z" {
		t.Fatalf("%+v", u)
	}
	if len(u.Log) > 8<<10 || !strings.HasSuffix(u.Log, "did not start\n") || !strings.HasPrefix(u.Log, "old line\n") {
		t.Fatalf("log tail: %d bytes, %q...", len(u.Log), u.Log[:20])
	}
	// a finished update does not block the next one
	e.expect(t, e.send(t, "POST", "/admin/system/update", e.tok, `{"channel":"release"}`), 202, "")
}
