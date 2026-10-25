package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/db"
	"stonerspots/backend/internal/photos"
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

	storage := photos.NewLocalStorage(cfg.UploadDir, strings.TrimRight(cfg.PublicBaseURL, "/")+"/api/v1/media")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start background cleanup of unattached photos older than 24h
	go photos.StartCleanupJob(ctx, d, storage, 24*time.Hour, 1*time.Hour)

	srv := server.HTTPServer(cfg.Addr, server.New(app.Deps{DB: d, Cfg: cfg}))
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		// let running requests (uploads) finish, then exit
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("shutdown: %v", err)
		}
	}()
	log.Printf("listening on %s", cfg.Addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
	log.Print("stopped")
}
