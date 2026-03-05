package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/config"
	"github.com/dgraham-io/cyaichi/server/internal/httpapi"
	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

func main() {
	cfg := config.FromEnv()
	workspaceRootAbs, dbPathAbs, err := prepareRuntimePaths(cfg)
	if err != nil {
		log.Fatalf("failed to prepare runtime paths: %v", err)
	}
	log.Printf("workspace root: %s", workspaceRootAbs)
	log.Printf("db path: %s", dbPathAbs)

	dbStore, err := store.Open(context.Background(), cfg.DBPath)
	if err != nil {
		log.Fatalf("failed to initialize db at %s: %v", cfg.DBPath, err)
	}
	defer func() {
		if closeErr := dbStore.Close(); closeErr != nil {
			log.Printf("db close error: %v", closeErr)
		}
	}()
	log.Printf("db ready at %s", cfg.DBPath)

	validator, err := schema.NewValidator()
	if err != nil {
		log.Fatalf("failed to initialize schema validator: %v", err)
	}
	log.Printf("schema validator ready")

	srv := &http.Server{
		Addr: cfg.HTTPAddr,
		Handler: httpapi.NewMux(
			dbStore,
			validator,
			cfg.WorkspaceRoot,
			cfg.VLLMBaseURL,
			cfg.VLLMKey,
			cfg.LLMModel,
			cfg.VLLMTimeout,
		),
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
	case err = <-serverErr:
		log.Fatalf("server failed: %v", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("server shutdown failed: %v", err)
	}

	log.Printf("server stopped")
}

func prepareRuntimePaths(cfg config.Config) (workspaceRootAbs, dbPathAbs string, err error) {
	workspaceRootAbs, err = filepath.Abs(cfg.WorkspaceRoot)
	if err != nil {
		return "", "", fmt.Errorf("resolve workspace root %q: %w", cfg.WorkspaceRoot, err)
	}
	if err := os.MkdirAll(workspaceRootAbs, 0o755); err != nil {
		return "", "", fmt.Errorf("create workspace root %q: %w", workspaceRootAbs, err)
	}

	if isSQLiteFilePath(cfg.DBPath) {
		dbPathAbs, err = filepath.Abs(cfg.DBPath)
		if err != nil {
			return "", "", fmt.Errorf("resolve db path %q: %w", cfg.DBPath, err)
		}
		dbDir := filepath.Dir(dbPathAbs)
		if err := os.MkdirAll(dbDir, 0o755); err != nil {
			return "", "", fmt.Errorf("create db dir %q: %w", dbDir, err)
		}
		return workspaceRootAbs, dbPathAbs, nil
	}

	return workspaceRootAbs, cfg.DBPath, nil
}

func isSQLiteFilePath(path string) bool {
	if path == "" {
		return false
	}
	trimmed := strings.TrimSpace(path)
	if trimmed == ":memory:" {
		return false
	}
	if strings.HasPrefix(trimmed, "file:") {
		return false
	}
	return true
}
