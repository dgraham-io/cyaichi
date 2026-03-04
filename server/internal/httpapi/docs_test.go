package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

func newTestDocsHandler(t *testing.T) *DocsHandler {
	t.Helper()

	dbPath := filepath.Join(t.TempDir(), "docs-handler.db")
	s, err := store.Open(context.Background(), dbPath)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Fatalf("close store: %v", err)
		}
	})

	validator, err := schema.NewValidator()
	if err != nil {
		t.Fatalf("load schemas: %v", err)
	}

	return &DocsHandler{
		store:     s,
		validator: validator,
	}
}

func TestDocsPutThenGetHappyPath(t *testing.T) {
	handler := newTestDocsHandler(t)

	body := `{
	  "doc_type": "memory",
	  "doc_id": "11111111-1111-1111-1111-111111111111",
	  "ver_id": "22222222-2222-2222-2222-222222222222",
	  "workspace_id": "33333333-3333-3333-3333-333333333333",
	  "created_at": "2026-03-03T00:00:00Z",
	  "body": {
	    "scope": "personal",
	    "type": "note",
	    "content": {
	      "format": "text/plain",
	      "body": "hello"
	    },
	    "provenance": {
	      "created_by": {
	        "kind": "user",
	        "id": "u1"
	      }
	    }
	  }
	}`

	putReq := httptest.NewRequest(http.MethodPut, "/v1/docs/memory/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222", strings.NewReader(body))
	putRR := httptest.NewRecorder()
	handler.Handle(putRR, putReq)
	if putRR.Code != http.StatusCreated {
		t.Fatalf("expected PUT status %d, got %d body=%s", http.StatusCreated, putRR.Code, putRR.Body.String())
	}

	getReq := httptest.NewRequest(http.MethodGet, "/v1/docs/memory/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222", nil)
	getRR := httptest.NewRecorder()
	handler.Handle(getRR, getReq)
	if getRR.Code != http.StatusOK {
		t.Fatalf("expected GET status %d, got %d body=%s", http.StatusOK, getRR.Code, getRR.Body.String())
	}
	if got := getRR.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected Content-Type application/json, got %q", got)
	}
	var got map[string]any
	if err := json.Unmarshal(getRR.Body.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON response: %v", err)
	}
	if got["doc_type"] != "memory" {
		t.Fatalf("expected doc_type memory, got %v", got["doc_type"])
	}
}

func TestDocsPutRejectsPathBodyMismatch(t *testing.T) {
	handler := newTestDocsHandler(t)

	body := `{
	  "doc_type": "memory",
	  "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
	  "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
	  "workspace_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
	  "created_at": "2026-03-03T00:00:00Z",
	  "body": {
	    "scope": "personal",
	    "type": "note",
	    "content": { "format": "text/plain", "body": "hello" },
	    "provenance": { "created_by": { "kind": "user" } }
	  }
	}`

	req := httptest.NewRequest(http.MethodPut, "/v1/docs/memory/DIFFERENT/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", strings.NewReader(body))
	rr := httptest.NewRecorder()
	handler.Handle(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, rr.Code)
	}
}

func TestDocsPutRejectsInvalidSchema(t *testing.T) {
	handler := newTestDocsHandler(t)

	body := `{
	  "doc_type": "memory",
	  "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
	  "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
	  "workspace_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
	  "created_at": "2026-03-03T00:00:00Z",
	  "body": {
	    "scope": "personal",
	    "type": "note",
	    "content": { "format": "text/plain", "body": "hello" }
	  }
	}`

	req := httptest.NewRequest(http.MethodPut, "/v1/docs/memory/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", strings.NewReader(body))
	rr := httptest.NewRecorder()
	handler.Handle(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
	}
}

func TestDocsPutDuplicateReturnsConflict(t *testing.T) {
	handler := newTestDocsHandler(t)

	body := `{
	  "doc_type": "memory",
	  "doc_id": "dddddddd-dddd-dddd-dddd-dddddddddddd",
	  "ver_id": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
	  "workspace_id": "ffffffff-ffff-ffff-ffff-ffffffffffff",
	  "created_at": "2026-03-03T00:00:00Z",
	  "body": {
	    "scope": "personal",
	    "type": "note",
	    "content": { "format": "text/plain", "body": "hello" },
	    "provenance": { "created_by": { "kind": "user" } }
	  }
	}`

	path := "/v1/docs/memory/dddddddd-dddd-dddd-dddd-dddddddddddd/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"

	firstReq := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body))
	firstRR := httptest.NewRecorder()
	handler.Handle(firstRR, firstReq)
	if firstRR.Code != http.StatusCreated {
		t.Fatalf("expected first status %d, got %d body=%s", http.StatusCreated, firstRR.Code, firstRR.Body.String())
	}

	secondReq := httptest.NewRequest(http.MethodPut, path, strings.NewReader(body))
	secondRR := httptest.NewRecorder()
	handler.Handle(secondRR, secondReq)
	if secondRR.Code != http.StatusConflict {
		t.Fatalf("expected second status %d, got %d body=%s", http.StatusConflict, secondRR.Code, secondRR.Body.String())
	}
}
