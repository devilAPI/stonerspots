// Command makeadmin grants or revokes the admin flag of a user.
//
//	DATABASE_URL=... go run ./cmd/makeadmin -email someone@example.com [-revoke]
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
	dsn := flag.String("db", os.Getenv("DATABASE_URL"), "database DSN (default: $DATABASE_URL)")
	flag.Parse()
	if *email == "" || *dsn == "" {
		fmt.Fprintln(os.Stderr, "usage: makeadmin -email user@example.com [-revoke] [-db DSN | $DATABASE_URL]")
		os.Exit(2)
	}
	d, err := db.Open(*dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: cannot connect to database: %v\n", err)
		os.Exit(1)
	}
	defer d.Close()
	os.Exit(run(context.Background(), d, *email, *revoke, os.Stdout, os.Stderr))
}
