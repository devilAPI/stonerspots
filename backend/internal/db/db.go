// Package db opens MariaDB connections and runs migrations.
package db

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/golang-migrate/migrate/v4"
	migmysql "github.com/golang-migrate/migrate/v4/database/mysql"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

// Open opens a pooled connection and verifies it with a ping.
func Open(dsn string) (*sql.DB, error) {
	d, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, err
	}
	d.SetMaxOpenConns(25)
	d.SetMaxIdleConns(10)
	d.SetConnMaxLifetime(5 * time.Minute)
	if err := d.Ping(); err != nil {
		d.Close()
		return nil, err
	}
	return d, nil
}

func newMigrate(dsn, dir string) (*migrate.Migrate, error) {
	// migrate closes the connection it is given, so use a dedicated one.
	// The DSN needs multiStatements=true.
	conn, err := Open(dsn)
	if err != nil {
		return nil, err
	}
	drv, err := migmysql.WithInstance(conn, &migmysql.Config{})
	if err != nil {
		conn.Close()
		return nil, err
	}
	m, err := migrate.NewWithDatabaseInstance("file://"+dir, "mysql", drv)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return m, nil
}

// Migrate applies all pending up migrations from dir. No pending migrations is not an error.
func Migrate(dsn, dir string) error {
	m, err := newMigrate(dsn, dir)
	if err != nil {
		return err
	}
	defer m.Close()
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return err
	}
	return nil
}

// MigrateDown rolls back every migration (used by tests).
func MigrateDown(dsn, dir string) error {
	m, err := newMigrate(dsn, dir)
	if err != nil {
		return err
	}
	defer m.Close()
	if err := m.Down(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return err
	}
	return nil
}
