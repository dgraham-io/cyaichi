package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	rr := httptest.NewRecorder()

	HealthHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rr.Code)
	}

	if got := rr.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected Content-Type application/json, got %q", got)
	}

	var got struct {
		OK      bool   `json:"ok"`
		Service string `json:"service"`
	}

	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("failed to decode body: %v", err)
	}

	if !got.OK {
		t.Fatalf("expected ok=true, got false")
	}

	if got.Service != "cyaichi" {
		t.Fatalf("expected service=cyaichi, got %q", got.Service)
	}
}
