package zones

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime/debug"
	"strings"
	"time"
)

// (variables: tests shorten them)
var (
	// extractEvery is how often the extract is downloaded and imported.
	extractEvery = 7 * 24 * time.Hour
	// extractRetry follows an import that failed.
	extractRetry = 6 * time.Hour
	// extractTimeout bounds one download and import.
	extractTimeout = 4 * time.Hour
)

// extractTTL is how long imported tiles count as fresh: two rounds, so one
// failed import does not send the map to Overpass.
const extractTTL = 2 * 7 * 24 * time.Hour

const (
	extractFile = "extract.osm.pbf"
	stateFile   = "state.json"
)

// extractState is what the last import left in the extract directory.
type extractState struct {
	ImportedAt time.Time `json:"imported_at"`
	Source     string    `json:"source"`
	Zones      int       `json:"zones"`
	Tiles      int       `json:"tiles"`
}

func readState(dir string) extractState {
	var st extractState
	if b, err := os.ReadFile(filepath.Join(dir, stateFile)); err == nil {
		_ = json.Unmarshal(b, &st)
	}
	return st
}

func writeState(dir string, st extractState) error {
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, stateFile), b, 0o644)
}

// UseExtract makes the service count its tiles fresh for extractTTL: they
// are rebuilt from the extract, Overpass is only asked for what is missing
// or overdue.
func (s *Service) UseExtract() { s.ttl = extractTTL }

// RunExtract keeps Germany's zones built from the OpenStreetMap extract at
// url: when the last import (recorded in dir) is extractEvery old, or there
// is none, it downloads the extract into dir, builds every German tile
// from it, saves them and deletes the download. Runs until ctx ends.
func (s *Service) RunExtract(ctx context.Context, url, dir string) {
	for {
		wait := time.Until(readState(dir).ImportedAt.Add(extractEvery))
		if wait > 0 && !sleepCtx(ctx, wait) {
			return
		}
		if err := s.importExtract(ctx, url, dir); err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("zones: extract: %v (next try in %s)", err, extractRetry)
			if !sleepCtx(ctx, extractRetry) {
				return
			}
		}
	}
}

func sleepCtx(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return true
	case <-ctx.Done():
		return false
	}
}

func (s *Service) importExtract(ctx context.Context, url, dir string) error {
	if s.store == nil {
		return errors.New("needs the database")
	}
	ctx, cancel := context.WithTimeout(ctx, extractTimeout)
	defer cancel()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	path := filepath.Join(dir, extractFile)
	defer os.Remove(path)
	// the import holds most of a gigabyte for a minute; give it back after
	defer debug.FreeOSMemory()

	start := time.Now()
	source, err := s.download(ctx, url, path)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}
	log.Printf("zones: extract: downloaded %s in %s", source, time.Since(start).Round(time.Second))

	start = time.Now()
	zones, err := zonesFromPBF(ctx, path)
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}
	os.Remove(path) // not needed any more; frees the disk before saving
	log.Printf("zones: extract: %d zones read in %s", len(zones), time.Since(start).Round(time.Second))

	start = time.Now()
	n, err := s.saveTiles(ctx, zones, s.now())
	if err != nil {
		return fmt.Errorf("save: %w (%d tiles saved)", err, n)
	}
	log.Printf("zones: extract: %d tiles saved in %s", n, time.Since(start).Round(time.Second))
	return writeState(dir, extractState{ImportedAt: s.now(), Source: source, Zones: len(zones), Tiles: n})
}

// saveTiles stores every German tile built from zones, and drops the memory
// cache so the next requests read the new tiles.
func (s *Service) saveTiles(ctx context.Context, zones []Zone, at time.Time) (int, error) {
	n := 0
	err := tilesFromZones(ctx, zones, func(t Tile, z []Zone) error {
		if err := s.store.save(ctx, t.Key(), tileData{Zones: z, FetchedAt: at}); err != nil {
			return err
		}
		n++
		return nil
	})
	s.mu.Lock()
	s.mem, s.order = map[string]tileData{}, nil
	s.mu.Unlock()
	return n, err
}

// download fetches url into path and checks it against the .md5 file next
// to it when the server has one (Geofabrik's mirrors do). It returns a description
// of the data (its Last-Modified).
func (s *Service) download(ctx context.Context, url, path string) (string, error) {
	resp, err := s.get(ctx, url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	part := path + ".part"
	f, err := os.Create(part)
	if err != nil {
		return "", err
	}
	defer os.Remove(part)
	sum := md5.New()
	if _, err := io.Copy(io.MultiWriter(f, sum), resp.Body); err != nil {
		f.Close()
		return "", err
	}
	if err := f.Close(); err != nil {
		return "", err
	}
	// Geofabrik redirects to a mirror, which has the .md5 (the main host
	// does not for -latest files): look next to where the data came from
	sumURLs := []string{resp.Request.URL.String()}
	if sumURLs[0] != url {
		sumURLs = append(sumURLs, url)
	}
	if want, ok := s.expectedMD5(ctx, sumURLs...); ok {
		if got := hex.EncodeToString(sum.Sum(nil)); got != want {
			return "", fmt.Errorf("checksum %s, expected %s", got, want)
		}
	}
	if err := os.Rename(part, path); err != nil {
		return "", err
	}
	source := host(url)
	if lm := resp.Header.Get("Last-Modified"); lm != "" {
		source += " of " + lm
	}
	return source, nil
}

// expectedMD5 reads the first of urls' .md5 files ("<hex>  <name>") that
// exists; false when there is none.
func (s *Service) expectedMD5(ctx context.Context, urls ...string) (string, bool) {
	for _, url := range urls {
		if sum, ok := s.readMD5(ctx, url+".md5"); ok {
			return sum, true
		}
	}
	return "", false
}

func (s *Service) readMD5(ctx context.Context, url string) (string, bool) {
	resp, err := s.get(ctx, url)
	if err != nil {
		return "", false
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1024))
	if err != nil {
		return "", false
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 || len(fields[0]) != 32 {
		return "", false
	}
	return strings.ToLower(fields[0]), true
}

func (s *Service) get(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", s.userAgent)
	// no client timeout: the extract takes minutes; ctx bounds it
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("%s: status %d", host(url), resp.StatusCode)
	}
	return resp, nil
}
