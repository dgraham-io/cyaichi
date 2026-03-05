package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dgraham-io/cyaichi/server/internal/config"
)

func TestPrepareRuntimePathsCreatesDefaultLocalDirs(t *testing.T) {
	tmp := t.TempDir()
	cfg := config.Config{
		DBPath:        "./.local/cyaichi.db",
		WorkspaceRoot: "./.local/workspace-data",
	}

	if err := chdir(t, tmp); err != nil {
		t.Fatalf("chdir temp dir: %v", err)
	}

	workspaceRootAbs, dbPathAbs, err := prepareRuntimePaths(cfg)
	if err != nil {
		t.Fatalf("prepare runtime paths: %v", err)
	}

	expectedWorkspace, err := filepath.EvalSymlinks(filepath.Join(tmp, ".local", "workspace-data"))
	if err != nil {
		t.Fatalf("eval symlinks workspace: %v", err)
	}
	if workspaceRootAbs != expectedWorkspace {
		t.Fatalf("workspace root mismatch: got %q want %q", workspaceRootAbs, expectedWorkspace)
	}
	expectedDBPath, err := filepath.EvalSymlinks(filepath.Join(tmp, ".local"))
	if err != nil {
		t.Fatalf("eval symlinks db dir: %v", err)
	}
	expectedDBPath = filepath.Join(expectedDBPath, "cyaichi.db")
	if dbPathAbs != expectedDBPath {
		t.Fatalf("db path mismatch: got %q want %q", dbPathAbs, expectedDBPath)
	}

	if !isDir(t, filepath.Dir(expectedWorkspace)) || !isDir(t, expectedWorkspace) {
		t.Fatalf("workspace root dir missing: %s", expectedWorkspace)
	}
	if !isDir(t, filepath.Dir(expectedDBPath)) {
		t.Fatalf("db parent dir missing: %s", filepath.Dir(expectedDBPath))
	}
}

func chdir(t *testing.T, dir string) error {
	t.Helper()
	wd, err := filepath.Abs(".")
	if err != nil {
		return err
	}
	if err := os.Chdir(dir); err != nil {
		return err
	}
	t.Cleanup(func() {
		_ = os.Chdir(wd)
	})
	return nil
}

func isDir(t *testing.T, path string) bool {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}
