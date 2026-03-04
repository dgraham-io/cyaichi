package config

import "os"

const (
	defaultHTTPAddr = ":8080"
	defaultLogLevel = "info"
	defaultDBPath   = "/tmp/cyaichi.db"
)

type Config struct {
	HTTPAddr string
	LogLevel string
	DBPath   string
}

func FromEnv() Config {
	return Config{
		HTTPAddr: envOrDefault("CYAI_HTTP_ADDR", defaultHTTPAddr),
		LogLevel: envOrDefault("CYAI_LOG_LEVEL", defaultLogLevel),
		DBPath:   envOrDefault("CYAI_DB_PATH", defaultDBPath),
	}
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
