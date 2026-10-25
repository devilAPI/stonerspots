package main

import (
	"log"
	"net/http"
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
	dir, err := filepath.Abs(cfg.MigrationsDir)
	if err != nil {
		log.Fatalf("migrations dir: %v", err)
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
