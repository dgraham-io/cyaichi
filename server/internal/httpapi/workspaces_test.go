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
	"github.com/google/uuid"
)

type apiTestHarness struct {
	mux   *http.ServeMux
	store *store.Store
}

func newAPITestHarness(t *testing.T) *apiTestHarness {
	t.Helper()

	dbPath := filepath.Join(t.TempDir(), "api.db")
	s, err := store.Open(context.Background(), dbPath)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Fatalf("close store: %v", err)
		}
	})

	v, err := schema.NewValidator()
	if err != nil {
		t.Fatalf("create validator: %v", err)
	}

	return &apiTestHarness{
		mux:   NewMux(s, v),
		store: s,
	}
}

func TestPostWorkspacesCreatesAndCanFetchViaDocs(t *testing.T) {
	h := newAPITestHarness(t)

	req := httptest.NewRequest(http.MethodPost, "/v1/workspaces", strings.NewReader(`{"name":"Test Workspace"}`))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, rr.Code, rr.Body.String())
	}

	var created struct {
		WorkspaceID string `json:"workspace_id"`
		DocID       string `json:"doc_id"`
		VerID       string `json:"ver_id"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if created.WorkspaceID == "" || created.DocID == "" || created.VerID == "" {
		t.Fatalf("expected non-empty ids in response: %+v", created)
	}
	if created.WorkspaceID != created.DocID {
		t.Fatalf("expected workspace_id and doc_id to match, got %s vs %s", created.WorkspaceID, created.DocID)
	}
	if _, err := uuid.Parse(created.WorkspaceID); err != nil {
		t.Fatalf("workspace_id is not uuid: %v", err)
	}
	if _, err := uuid.Parse(created.VerID); err != nil {
		t.Fatalf("ver_id is not uuid: %v", err)
	}

	getReq := httptest.NewRequest(http.MethodGet, "/v1/docs/workspace/"+created.DocID+"/"+created.VerID, nil)
	getRR := httptest.NewRecorder()
	h.mux.ServeHTTP(getRR, getReq)

	if getRR.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, getRR.Code, getRR.Body.String())
	}

	var workspaceDoc struct {
		DocType     string `json:"doc_type"`
		DocID       string `json:"doc_id"`
		WorkspaceID string `json:"workspace_id"`
		Body        struct {
			Name  string            `json:"name"`
			Heads map[string]string `json:"heads"`
		} `json:"body"`
	}
	if err := json.Unmarshal(getRR.Body.Bytes(), &workspaceDoc); err != nil {
		t.Fatalf("decode workspace doc: %v", err)
	}

	if workspaceDoc.DocType != "workspace" {
		t.Fatalf("expected doc_type workspace, got %q", workspaceDoc.DocType)
	}
	if workspaceDoc.DocID != created.DocID || workspaceDoc.WorkspaceID != created.WorkspaceID {
		t.Fatalf("unexpected workspace identity in stored doc")
	}
	if workspaceDoc.Body.Name != "Test Workspace" {
		t.Fatalf("expected name Test Workspace, got %q", workspaceDoc.Body.Name)
	}
	if len(workspaceDoc.Body.Heads) != 0 {
		t.Fatalf("expected empty heads map, got %v", workspaceDoc.Body.Heads)
	}
}

func TestPutWorkspaceHeadWritesHeadAndCreatesNewWorkspaceVersion(t *testing.T) {
	h := newAPITestHarness(t)

	createReq := httptest.NewRequest(http.MethodPost, "/v1/workspaces", strings.NewReader(`{"name":"Head Test"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("workspace create failed: %d body=%s", createRR.Code, createRR.Body.String())
	}

	var created struct {
		WorkspaceID string `json:"workspace_id"`
		DocID       string `json:"doc_id"`
		VerID       string `json:"ver_id"`
	}
	if err := json.Unmarshal(createRR.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	targetDocID := uuid.NewString()
	targetVerID := uuid.NewString()
	putBody := `{"ver_id":"` + targetVerID + `"}`

	setReq := httptest.NewRequest(http.MethodPut, "/v1/workspaces/"+created.WorkspaceID+"/heads/"+targetDocID, strings.NewReader(putBody))
	setReq.Header.Set("Content-Type", "application/json")
	setRR := httptest.NewRecorder()
	h.mux.ServeHTTP(setRR, setReq)
	if setRR.Code != http.StatusOK {
		t.Fatalf("set head failed: %d body=%s", setRR.Code, setRR.Body.String())
	}

	var updated struct {
		WorkspaceID string `json:"workspace_id"`
		DocID       string `json:"doc_id"`
		VerID       string `json:"ver_id"`
	}
	if err := json.Unmarshal(setRR.Body.Bytes(), &updated); err != nil {
		t.Fatalf("decode set head response: %v", err)
	}
	if updated.WorkspaceID != created.WorkspaceID || updated.DocID != created.DocID {
		t.Fatalf("unexpected workspace identity in set head response")
	}
	if updated.VerID == created.VerID {
		t.Fatalf("expected new workspace ver_id to differ from previous version")
	}

	headVer, err := h.store.GetHead(context.Background(), created.WorkspaceID, targetDocID)
	if err != nil {
		t.Fatalf("get head from store: %v", err)
	}
	if headVer != targetVerID {
		t.Fatalf("unexpected stored head ver_id: got %q want %q", headVer, targetVerID)
	}

	getDocReq := httptest.NewRequest(http.MethodGet, "/v1/docs/workspace/"+created.DocID+"/"+updated.VerID, nil)
	getDocRR := httptest.NewRecorder()
	h.mux.ServeHTTP(getDocRR, getDocReq)
	if getDocRR.Code != http.StatusOK {
		t.Fatalf("fetch updated workspace doc failed: %d body=%s", getDocRR.Code, getDocRR.Body.String())
	}

	var workspaceDoc struct {
		Parents []string `json:"parents"`
		Body    struct {
			Heads map[string]string `json:"heads"`
		} `json:"body"`
	}
	if err := json.Unmarshal(getDocRR.Body.Bytes(), &workspaceDoc); err != nil {
		t.Fatalf("decode updated workspace doc: %v", err)
	}
	if len(workspaceDoc.Parents) != 1 || workspaceDoc.Parents[0] != created.VerID {
		t.Fatalf("expected parents [%s], got %v", created.VerID, workspaceDoc.Parents)
	}
	if workspaceDoc.Body.Heads[targetDocID] != targetVerID {
		t.Fatalf("expected heads[%s]=%s, got %q", targetDocID, targetVerID, workspaceDoc.Body.Heads[targetDocID])
	}
}

func TestGetWorkspaceHeadReturnsExpectedVersion(t *testing.T) {
	h := newAPITestHarness(t)

	createReq := httptest.NewRequest(http.MethodPost, "/v1/workspaces", strings.NewReader(`{"name":"Get Head Test"}`))
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createRR, createReq)
	if createRR.Code != http.StatusCreated {
		t.Fatalf("workspace create failed: %d body=%s", createRR.Code, createRR.Body.String())
	}

	var created struct {
		WorkspaceID string `json:"workspace_id"`
	}
	if err := json.Unmarshal(createRR.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	targetDocID := uuid.NewString()
	targetVerID := uuid.NewString()
	setReq := httptest.NewRequest(http.MethodPut, "/v1/workspaces/"+created.WorkspaceID+"/heads/"+targetDocID, strings.NewReader(`{"ver_id":"`+targetVerID+`"}`))
	setReq.Header.Set("Content-Type", "application/json")
	setRR := httptest.NewRecorder()
	h.mux.ServeHTTP(setRR, setReq)
	if setRR.Code != http.StatusOK {
		t.Fatalf("set head failed: %d body=%s", setRR.Code, setRR.Body.String())
	}

	getReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+created.WorkspaceID+"/heads/"+targetDocID, nil)
	getRR := httptest.NewRecorder()
	h.mux.ServeHTTP(getRR, getReq)
	if getRR.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, getRR.Code, getRR.Body.String())
	}

	var got struct {
		VerID string `json:"ver_id"`
	}
	if err := json.Unmarshal(getRR.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode get head response: %v", err)
	}
	if got.VerID != targetVerID {
		t.Fatalf("unexpected ver_id: got %q want %q", got.VerID, targetVerID)
	}
}
