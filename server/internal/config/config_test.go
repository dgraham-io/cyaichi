package config

import (
	"testing"
)

func TestFromEnvDefaults(t *testing.T) {
	t.Setenv("CYAI_HTTP_ADDR", "")
	t.Setenv("CYAI_LOG_LEVEL", "")
	t.Setenv("CYAI_DB_PATH", "")
	t.Setenv("CYAI_WORKSPACE_ROOT", "")
	t.Setenv("CYAI_VLLM_BASE_URL", "")
	t.Setenv("VLLM_URL", "")
	t.Setenv("VLLM_KEY", "")
	t.Setenv("CYAI_LLM_MODEL", "")
	t.Setenv("CYAI_VLLM_TIMEOUT_SECONDS", "")

	cfg := FromEnv()

	if cfg.DBPath != "./.local/cyaichi.db" {
		t.Fatalf("expected default DB path ./\\.local/cyaichi.db, got %q", cfg.DBPath)
	}
	if cfg.WorkspaceRoot != "./.local/workspace-data" {
		t.Fatalf("expected default workspace root ./\\.local/workspace-data, got %q", cfg.WorkspaceRoot)
	}
}
