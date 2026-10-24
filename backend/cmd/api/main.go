package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/db"
	"stonerspots/backend/internal/server"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	dir := os.Getenv("MIGRATIONS_DIR")
	if dir == "" {
		dir, _ = filepath.Abs("migrations")
	}
	if err := db.Migrate(cfg.DatabaseURL, dir); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	d, err := db.Open(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer d.Close()

	log.Printf("listening on %s", cfg.Addr)
	log.Fatal(http.ListenAndServe(cfg.Addr, server.New(app.Deps{DB: d, Cfg: cfg})))
}
