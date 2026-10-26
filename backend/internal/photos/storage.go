package photos

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Storage abstracts where processed photo files live.
type Storage interface {
	Put(ctx context.Context, key string, r io.Reader) error
	Open(ctx context.Context, key string) (io.ReadCloser, error)
	Delete(ctx context.Context, key string) error
	URL(key string) string
}

type localStorage struct {
	dir     string
	baseURL string // full URL prefix under which keys are served, no trailing slash
}

// NewLocalStorage stores files under dir; URL(key) is baseURL + "/" + key.
func NewLocalStorage(dir, baseURL string) Storage {
	return &localStorage{dir: dir, baseURL: strings.TrimRight(baseURL, "/")}
}

func (s *localStorage) path(key string) (string, error) {
	clean := filepath.Clean(filepath.FromSlash(key))
	if key == "" || filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("invalid storage key %q", key)
	}
	return filepath.Join(s.dir, clean), nil
}

func (s *localStorage) Put(ctx context.Context, key string, r io.Reader) error {
	p, err := s.path(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(p), ".upload-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := io.Copy(tmp, r); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), p)
}

func (s *localStorage) Open(ctx context.Context, key string) (io.ReadCloser, error) {
	p, err := s.path(key)
	if err != nil {
		return nil, err
	}
	return os.Open(p)
}

func (s *localStorage) Delete(ctx context.Context, key string) error {
	p, err := s.path(key)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (s *localStorage) URL(key string) string { return s.baseURL + "/" + key }
