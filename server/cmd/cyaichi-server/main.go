package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/config"
	"github.com/dgraham-io/cyaichi/server/internal/httpapi"
)

func main() {
	cfg := config.FromEnv()

	srv := &http.Server{
		Addr:    cfg.HTTPAddr,
		Handler: httpapi.NewMux(),
	}

	serverErr := make(chan error, 1)
	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	log.Printf("cyaichi server starting on %s (log_level=%s)", cfg.HTTPAddr, cfg.LogLevel)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case <-ctx.Done():
		log.Printf("shutdown signal received")
	case err := <-serverErr:
		log.Fatalf("server failed: %v", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("server shutdown failed: %v", err)
	}

	log.Printf("server stopped")
}
