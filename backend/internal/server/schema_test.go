package server_test

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"stonerspots/backend/internal/db"
	"stonerspots/backend/internal/testutil"
)

const schemaHeader = `-- Stonerspots database layout (MariaDB 11.4), for reference and for setting up
-- a database by hand:  mariadb -u root -p stonerspots < schema.example.sql
--
-- GENERATED from migrations/ - do not edit. The migrations are the source of
-- truth and the API applies them on start; regenerate this file with
--   UPDATE_SCHEMA=1 go test ./internal/server -run TestSchemaFile
-- The schema_migrations row marks every migration as applied, so the API
-- does not try to run them again on a database created from this file.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;
`

var autoIncrement = regexp.MustCompile(` AUTO_INCREMENT=\d+`)

// dumpSchema renders the tables of d as CREATE statements in name order.
func dumpSchema(t *testing.T, d *sql.DB) string {
	t.Helper()
	rows, err := d.Query(`SELECT table_name FROM information_schema.tables
		WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY table_name`)
	if err != nil {
		t.Fatal(err)
	}
	var tables []string
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			t.Fatal(err)
		}
		tables = append(tables, n)
	}
	rows.Close()

	var b strings.Builder
	b.WriteString(schemaHeader)
	for _, tbl := range tables {
		var name, create string
		if err := d.QueryRow("SHOW CREATE TABLE `"+tbl+"`").Scan(&name, &create); err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(&b, "\nDROP TABLE IF EXISTS `%s`;\n%s;\n", tbl, autoIncrement.ReplaceAllString(create, ""))
	}
	var version int
	var dirty bool
	if err := d.QueryRow(`SELECT version, dirty FROM schema_migrations`).Scan(&version, &dirty); err != nil {
		t.Fatal(err)
	}
	fmt.Fprintf(&b, "\nINSERT INTO `schema_migrations` (`version`, `dirty`) VALUES (%d, %d);\n", version, boolInt(dirty))
	dumpTagCatalog(t, d, &b)
	b.WriteString("\nSET FOREIGN_KEY_CHECKS = 1;\n")
	return b.String()
}

// dumpTagCatalog writes the tag catalog rows the migrations seed: without
// them a database made from the file would have no tags at all.
func dumpTagCatalog(t *testing.T, d *sql.DB, b *strings.Builder) {
	t.Helper()
	rows, err := d.Query(`SELECT tag, name_de, name_en, icon, sort FROM tags ORDER BY sort, tag`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	q := func(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
	var vals []string
	for rows.Next() {
		var tag, de, en, icon string
		var sort int
		if err := rows.Scan(&tag, &de, &en, &icon, &sort); err != nil {
			t.Fatal(err)
		}
		vals = append(vals, fmt.Sprintf("  (%s, %s, %s, %s, %d)", q(tag), q(de), q(en), q(icon), sort))
	}
	if len(vals) == 0 {
		return
	}
	fmt.Fprintf(b, "\nINSERT INTO `tags` (`tag`, `name_de`, `name_en`, `icon`, `sort`) VALUES\n%s;\n", strings.Join(vals, ",\n"))
}

func boolInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

// TestSchemaFile keeps schema.example.sql in sync with the migrations and
// checks that a database created from it is identical and needs no migration.
func TestSchemaFile(t *testing.T) {
	path := filepath.Join(testutil.MigrationsDir(), "..", "schema.example.sql")
	want := dumpSchema(t, testutil.NewDB(t))

	if os.Getenv("UPDATE_SCHEMA") != "" {
		if err := os.WriteFile(path, []byte(want), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != want {
		t.Fatalf("schema.example.sql is out of date with migrations/; regenerate it with\n" +
			"  UPDATE_SCHEMA=1 go test ./internal/server -run TestSchemaFile")
	}

	d, dsn := testutil.NewEmptyDB(t)
	if _, err := d.Exec(string(got)); err != nil {
		t.Fatalf("loading schema.example.sql: %v", err)
	}
	if err := db.Migrate(dsn, testutil.MigrationsDir()); err != nil {
		t.Fatalf("migrate on a database made from the file: %v", err)
	}
	if again := dumpSchema(t, d); again != want {
		t.Fatal("database created from schema.example.sql differs from the migrated one")
	}
}
