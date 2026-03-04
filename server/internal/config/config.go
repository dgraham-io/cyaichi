package config

import "os"

const (
	defaultHTTPAddr      = ":8080"
	defaultLogLevel      = "info"
	defaultDBPath        = "/tmp/cyaichi.db"
	defaultWorkspaceRoot = "./workspace-data"
	defaultLLMModel      = "gpt-oss120:b"
)

type Config struct {
	HTTPAddr      string
	LogLevel      string
	DBPath        string
	WorkspaceRoot string
	VLLMBaseURL   string
	VLLMKey       string
	LLMModel      string
}

func FromEnv() Config {
	return Config{
		HTTPAddr:      envOrDefault("CYAI_HTTP_ADDR", defaultHTTPAddr),
		LogLevel:      envOrDefault("CYAI_LOG_LEVEL", defaultLogLevel),
		DBPath:        envOrDefault("CYAI_DB_PATH", defaultDBPath),
		WorkspaceRoot: envOrDefault("CYAI_WORKSPACE_ROOT", defaultWorkspaceRoot),
		VLLMBaseURL:   envOrDefault("CYAI_VLLM_BASE_URL", ""),
		VLLMKey:       envOrDefault("VLLM_KEY", ""),
		LLMModel:      envOrDefault("CYAI_LLM_MODEL", defaultLLMModel),
	}
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
