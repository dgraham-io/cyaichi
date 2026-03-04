package config

import (
	"os"
	"strconv"
)

const (
	defaultHTTPAddr      = ":8080"
	defaultLogLevel      = "info"
	defaultDBPath        = "/tmp/cyaichi.db"
	defaultWorkspaceRoot = "./workspace-data"
	defaultLLMModel      = "gpt-oss120:b"
	defaultVLLMTimeout   = 120
)

type Config struct {
	HTTPAddr      string
	LogLevel      string
	DBPath        string
	WorkspaceRoot string
	VLLMBaseURL   string
	VLLMKey       string
	LLMModel      string
	VLLMTimeout   int
}

func FromEnv() Config {
	return Config{
		HTTPAddr:      envOrDefault("CYAI_HTTP_ADDR", defaultHTTPAddr),
		LogLevel:      envOrDefault("CYAI_LOG_LEVEL", defaultLogLevel),
		DBPath:        envOrDefault("CYAI_DB_PATH", defaultDBPath),
		WorkspaceRoot: envOrDefault("CYAI_WORKSPACE_ROOT", defaultWorkspaceRoot),
		VLLMBaseURL:   envOrDefault("CYAI_VLLM_BASE_URL", envOrDefault("VLLM_URL", "")),
		VLLMKey:       envOrDefault("VLLM_KEY", ""),
		LLMModel:      envOrDefault("CYAI_LLM_MODEL", defaultLLMModel),
		VLLMTimeout:   envOrDefaultInt("CYAI_VLLM_TIMEOUT_SECONDS", defaultVLLMTimeout),
	}
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envOrDefaultInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
