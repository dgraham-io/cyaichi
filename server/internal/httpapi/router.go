package httpapi

import "net/http"

func NewMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", HealthHandler)
	return mux
}
