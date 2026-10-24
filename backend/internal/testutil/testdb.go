// Package testutil has helpers for tests that run against a real MariaDB.
//
// Test DSN (needs privileges to CREATE/DROP DATABASE, hence root; start the
// DB with `docker compose up -d` from the repo root):
//
//	root:stonerspots@tcp(127.0.0.1:3307)/?parseTime=true&multiStatements=true
//
// Override it with the TEST_DATABASE_URL environment variable. The DSN must
// not name a database: every test gets its own throwaway schema.
package testutil

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/go-sql-driver/mysql"

	"stonerspots/backend/internal/db"
)

// DefaultTestDSN is used when TEST_DATABASE_URL is not set.
const DefaultTestDSN = "root:stonerspots@tcp(127.0.0.1:3307)/?parseTime=true&multiStatements=true"

// MigrationsDir returns the absolute path of backend/migrations.
func MigrationsDir() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "..", "..", "migrations")
}

// NewEmptyDB creates a throwaway schema WITHOUT running migrations and returns
// a connection to it plus its DSN (for db.Migrate). The schema is dropped on cleanup.
func NewEmptyDB(t *testing.T) (*sql.DB, string) {
	t.Helper()
	base := os.Getenv("TEST_DATABASE_URL")
	if base == "" {
		base = DefaultTestDSN
	}
	cfg, err := mysql.ParseDSN(base)
	if err != nil {
		t.Fatalf("testutil: bad TEST_DATABASE_URL: %v", err)
	}
	cfg.ParseTime = true
	cfg.MultiStatements = true

	admin := *cfg
	admin.DBName = ""
	adminDB, err := db.Open(admin.FormatDSN())
	if err != nil {
		t.Fatalf("testutil: MariaDB not reachable (%v). Start it with `docker compose up -d` "+
			"or set TEST_DATABASE_URL (default %s)", err, DefaultTestDSN)
	}
	var b [6]byte
	_, _ = rand.Read(b[:])
	name := "stonerspots_test_" + hex.EncodeToString(b[:])
	if _, err := adminDB.Exec(fmt.Sprintf("CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", name)); err != nil {
		adminDB.Close()
		t.Fatalf("testutil: cannot create schema (is the DSN user allowed to CREATE DATABASE?): %v", err)
	}

	cfg.DBName = name
	dsn := cfg.FormatDSN()
	d, err := db.Open(dsn)
	if err != nil {
		adminDB.Exec(fmt.Sprintf("DROP DATABASE `%s`", name))
		adminDB.Close()
		t.Fatalf("testutil: open test schema: %v", err)
	}
	t.Cleanup(func() {
		d.Close()
		adminDB.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS `%s`", name))
		adminDB.Close()
	})
	return d, dsn
}

// NewDB creates a throwaway schema, runs all migrations and returns a connection.
func NewDB(t *testing.T) *sql.DB {
	t.Helper()
	d, dsn := NewEmptyDB(t)
	if err := db.Migrate(dsn, MigrationsDir()); err != nil {
		t.Fatalf("testutil: migrate: %v", err)
	}
	return d
}
