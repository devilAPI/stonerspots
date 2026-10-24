//go:build tools

// Package tools pins dependencies that later tasks use, so `go mod tidy`
// keeps them in go.mod before any non-test file imports them.
package tools

import (
	_ "github.com/disintegration/imaging"
	_ "golang.org/x/crypto/bcrypt"
)
