package admin

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"stonerspots/backend/internal/httpx"
)

// Backend updates from the admin page. The API runs unprivileged and
// cannot replace or restart itself, so it only asks: it writes the wanted
// channel to <update_dir>/request/channel. A root systemd path unit set up
// by install-backend.sh notices the file, deletes it, runs the installed
// install-backend.sh for that channel and reports progress in
// <update_dir>/status/ (state, log), which this reads back.

// maxLogBytes is how much of the end of the update log is sent.
const maxLogBytes = 8 << 10

type updateStatus struct {
	// idle (never ran), pending (asked, not started), running, done, failed
	State      string     `json:"state"`
	Channel    string     `json:"channel,omitempty"`
	From       string     `json:"from,omitempty"`
	To         string     `json:"to,omitempty"`
	StartedAt  *time.Time `json:"started_at,omitempty"`
	FinishedAt *time.Time `json:"finished_at,omitempty"`
	Log        string     `json:"log"`
}

type systemInfo struct {
	// Version is the installed release tag (e.g. dev-42); empty when not
	// installed by install-backend.sh.
	Version        string       `json:"version"`
	UpdatesEnabled bool         `json:"updates_enabled"`
	Update         updateStatus `json:"update"`
}

func (h handler) system(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, http.StatusOK, h.systemInfo())
}

func (h handler) requestUpdate(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Channel string `json:"channel"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&in); err != nil {
		badBody(w)
		return
	}
	if in.Channel != "release" && in.Channel != "dev" {
		httpx.Error(w, http.StatusBadRequest, "invalid_channel", "channel must be release or dev")
		return
	}
	info := h.systemInfo()
	if !info.UpdatesEnabled {
		httpx.Error(w, http.StatusServiceUnavailable, "updates_disabled", "this server is not set up for updates from the admin page")
		return
	}
	if info.Update.State == "pending" || info.Update.State == "running" {
		httpx.Error(w, http.StatusConflict, "update_in_progress", "an update is already under way")
		return
	}
	// temp file + rename: the watcher only ever sees a complete request
	dir := filepath.Join(h.updateDir, "request")
	tmp, err := os.CreateTemp(dir, ".channel-*")
	if err != nil {
		serverError(w)
		return
	}
	_, werr := tmp.WriteString(in.Channel + "\n")
	cerr := tmp.Close()
	if werr != nil || cerr != nil || os.Rename(tmp.Name(), filepath.Join(dir, "channel")) != nil {
		_ = os.Remove(tmp.Name())
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusAccepted, h.systemInfo())
}

func (h handler) systemInfo() systemInfo {
	info := systemInfo{Version: readTrimmed(h.versionFile), Update: updateStatus{State: "idle"}}
	if h.updateDir == "" {
		return info
	}
	if st, err := os.Stat(filepath.Join(h.updateDir, "request")); err != nil || !st.IsDir() {
		return info
	}
	info.UpdatesEnabled = true
	status := filepath.Join(h.updateDir, "status")
	info.Update = readState(filepath.Join(status, "state"))
	info.Update.Log = tail(filepath.Join(status, "log"), maxLogBytes)
	if _, err := os.Stat(filepath.Join(h.updateDir, "request", "channel")); err == nil &&
		info.Update.State != "running" {
		info.Update.State = "pending"
	}
	return info
}

// readState parses the key=value lines the update runner writes.
func readState(path string) updateStatus {
	st := updateStatus{State: "idle"}
	f, err := os.Open(path)
	if err != nil {
		return st
	}
	defer f.Close()
	sc := bufio.NewScanner(io.LimitReader(f, 4<<10))
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), "=")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		at := func() *time.Time {
			t, err := time.Parse(time.RFC3339, v)
			if err != nil {
				return nil
			}
			t = t.UTC()
			return &t
		}
		switch strings.TrimSpace(k) {
		case "state":
			if v == "running" || v == "done" || v == "failed" {
				st.State = v
			}
		case "channel":
			st.Channel = v
		case "from":
			st.From = v
		case "to":
			st.To = v
		case "started":
			st.StartedAt = at()
		case "finished":
			st.FinishedAt = at()
		}
	}
	return st
}

func readTrimmed(path string) string {
	if path == "" {
		return ""
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// tail returns at most the last n bytes of the file, from a line start.
func tail(path string, n int64) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return ""
	}
	off := max(st.Size()-n, 0)
	b := make([]byte, st.Size()-off)
	if _, err := f.ReadAt(b, off); err != nil && !errors.Is(err, io.EOF) {
		return ""
	}
	s := string(b)
	if off > 0 {
		if i := strings.IndexByte(s, '\n'); i >= 0 {
			s = s[i+1:]
		}
	}
	return s
}

// versionFileNextTo is the VERSION file install-backend.sh writes next to
// the api binary.
func versionFileNextTo() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Join(filepath.Dir(exe), "VERSION")
}
