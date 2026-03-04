package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNotesCreateAndGet(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Notes Workspace")

	createBody := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "scope":"personal",
	  "title":"First Note",
	  "body":"# hello\nthis is a note"
	}`
	createReq := httptest.NewRequest(http.MethodPost, "/v1/notes", strings.NewReader(createBody))
	createReq.Header.Set("Content-Type", "application/json")
	createRR := httptest.NewRecorder()
	h.mux.ServeHTTP(createRR, createReq)

	if createRR.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, createRR.Code, createRR.Body.String())
	}

	var created struct {
		DocID string `json:"doc_id"`
		VerID string `json:"ver_id"`
	}
	if err := json.Unmarshal(createRR.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode create note response: %v", err)
	}
	if created.DocID == "" || created.VerID == "" {
		t.Fatalf("expected non-empty doc_id/ver_id")
	}

	getReq := httptest.NewRequest(http.MethodGet, "/v1/notes/"+created.DocID+"/"+created.VerID, nil)
	getRR := httptest.NewRecorder()
	h.mux.ServeHTTP(getRR, getReq)

	if getRR.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, getRR.Code, getRR.Body.String())
	}

	var noteDoc struct {
		DocType string `json:"doc_type"`
		Body    struct {
			Type    string `json:"type"`
			Scope   string `json:"scope"`
			Content struct {
				Format string `json:"format"`
				Body   string `json:"body"`
			} `json:"content"`
		} `json:"body"`
	}
	if err := json.Unmarshal(getRR.Body.Bytes(), &noteDoc); err != nil {
		t.Fatalf("decode note doc: %v", err)
	}
	if noteDoc.DocType != "memory" {
		t.Fatalf("expected doc_type memory, got %q", noteDoc.DocType)
	}
	if noteDoc.Body.Type != "note" || noteDoc.Body.Scope != "personal" {
		t.Fatalf("unexpected note body type/scope")
	}
	if noteDoc.Body.Content.Format != "markdown" {
		t.Fatalf("expected markdown format, got %q", noteDoc.Body.Content.Format)
	}
}

func TestWorkspaceNotesListAndWorkspaceSeparation(t *testing.T) {
	h := newAPITestHarness(t)
	workspaceA := createWorkspaceViaAPI(t, h, "Workspace A")
	workspaceB := createWorkspaceViaAPI(t, h, "Workspace B")

	create := func(workspaceID, title, body string) {
		t.Helper()
		reqBody := `{
		  "workspace_id":"` + workspaceID + `",
		  "scope":"team",
		  "title":"` + title + `",
		  "body":"` + body + `"
		}`
		req := httptest.NewRequest(http.MethodPost, "/v1/notes", strings.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rr := httptest.NewRecorder()
		h.mux.ServeHTTP(rr, req)
		if rr.Code != http.StatusCreated {
			t.Fatalf("create note failed: %d body=%s", rr.Code, rr.Body.String())
		}
	}

	create(workspaceA.WorkspaceID, "A1", "note in workspace A")
	create(workspaceB.WorkspaceID, "B1", "note in workspace B")

	listReq := httptest.NewRequest(http.MethodGet, "/v1/workspaces/"+workspaceA.WorkspaceID+"/notes", nil)
	listRR := httptest.NewRecorder()
	h.mux.ServeHTTP(listRR, listReq)

	if listRR.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, listRR.Code, listRR.Body.String())
	}

	var listed struct {
		Items []struct {
			DocID       string `json:"doc_id"`
			Title       string `json:"title"`
			Scope       string `json:"scope"`
			BodyPreview string `json:"body_preview"`
		} `json:"items"`
	}
	if err := json.Unmarshal(listRR.Body.Bytes(), &listed); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	if len(listed.Items) != 1 {
		t.Fatalf("expected 1 note for workspace A, got %d", len(listed.Items))
	}
	if listed.Items[0].Title != "A1" {
		t.Fatalf("expected title A1, got %q", listed.Items[0].Title)
	}
	if listed.Items[0].Scope != "team" {
		t.Fatalf("expected scope team, got %q", listed.Items[0].Scope)
	}
	if !strings.Contains(listed.Items[0].BodyPreview, "workspace A") {
		t.Fatalf("expected workspace A preview, got %q", listed.Items[0].BodyPreview)
	}
}
