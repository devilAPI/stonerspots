// Command makeadmin grants or revokes the admin flag of a user.
//
//	go run ./cmd/makeadmin -email someone@example.com [-revoke]
//
// The database comes from -db, $DATABASE_URL or the config file (see config.example.yaml).
package main

import (
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/db"
)

// run does the work and returns the process exit code.
func run(ctx context.Context, d *sql.DB, email string, revoke bool, out, errOut io.Writer) int {
	err := auth.SetAdmin(ctx, d, email, !revoke)
	switch {
	case errors.Is(err, auth.ErrNoSuchUser):
		fmt.Fprintf(errOut, "error: no user with email %q\n", email)
		return 1
	case err != nil:
		fmt.Fprintf(errOut, "error: %v\n", err)
		return 1
	case revoke:
		fmt.Fprintf(out, "revoked admin from %s\n", email)
	default:
		fmt.Fprintf(out, "granted admin to %s\n", email)
	}
	return 0
}

func main() {
	email := flag.String("email", "", "email of the user (required)")
	revoke := flag.Bool("revoke", false, "revoke admin instead of granting it")
	dsn := flag.String("db", "", "database DSN (default: $DATABASE_URL, then the config file)")
	flag.Parse()
	if *email == "" {
		fmt.Fprintln(os.Stderr, "usage: makeadmin -email user@example.com [-revoke] [-db DSN]")
		os.Exit(2)
	}
	if *dsn == "" {
		cfg, err := config.Read()
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		*dsn = cfg.DatabaseURL
	}
	d, err := db.Open(*dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: cannot connect to database: %v\n", err)
		os.Exit(1)
	}
	defer d.Close()
	os.Exit(run(context.Background(), d, *email, *revoke, os.Stdout, os.Stderr))
}
