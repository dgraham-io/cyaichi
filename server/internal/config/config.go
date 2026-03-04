package config

import "os"

const (
	defaultHTTPAddr = ":8080"
	defaultLogLevel = "info"
)

type Config struct {
	HTTPAddr string
	LogLevel string
}

func FromEnv() Config {
	return Config{
		HTTPAddr: envOrDefault("CYAI_HTTP_ADDR", defaultHTTPAddr),
		LogLevel: envOrDefault("CYAI_LOG_LEVEL", defaultLogLevel),
	}
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
