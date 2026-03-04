package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
	"github.com/google/uuid"
)

type NotesHandler struct {
	store     *store.Store
	validator *schema.Validator
}

type createNoteRequest struct {
	WorkspaceID string `json:"workspace_id"`
	Scope       string `json:"scope"`
	Title       string `json:"title"`
	Body        string `json:"body"`
}

type createNoteResponse struct {
	DocID string `json:"doc_id"`
	VerID string `json:"ver_id"`
}

type listNotesResponse struct {
	Items []listNoteItem `json:"items"`
}

type listNoteItem struct {
	DocID       string `json:"doc_id"`
	VerID       string `json:"ver_id"`
	CreatedAt   string `json:"created_at"`
	Title       string `json:"title,omitempty"`
	Scope       string `json:"scope"`
	BodyPreview string `json:"body_preview"`
}

func (h *NotesHandler) Handle(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/v1/notes" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		h.handleCreateNote(w, r)
		return
	}

	docID, verID, ok := parseNotePath(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	h.handleGetNote(w, r, docID, verID)
}

func (h *NotesHandler) HandleWorkspaceList(w http.ResponseWriter, r *http.Request, workspaceID string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if _, err := uuid.Parse(workspaceID); err != nil {
		http.Error(w, "workspace_id must be a valid UUID", http.StatusBadRequest)
		return
	}
	if _, err := h.store.GetLatestWorkspaceDoc(r.Context(), workspaceID); errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	} else if err != nil {
		http.Error(w, "failed to fetch workspace", http.StatusInternalServerError)
		return
	}

	rows, err := h.store.ListMemoryByWorkspace(r.Context(), workspaceID, 50, 0)
	if err != nil {
		http.Error(w, "failed to list notes", http.StatusInternalServerError)
		return
	}

	items := make([]listNoteItem, 0, len(rows))
	for _, row := range rows {
		var doc map[string]any
		if err := json.Unmarshal([]byte(row.JSON), &doc); err != nil {
			continue
		}
		body, _ := doc["body"].(map[string]any)
		docType, _ := body["type"].(string)
		if docType != "note" {
			continue
		}
		content, _ := body["content"].(map[string]any)
		bodyText, _ := content["body"].(string)
		scope, _ := body["scope"].(string)

		title := ""
		if meta, ok := doc["meta"].(map[string]any); ok {
			title, _ = meta["title"].(string)
		}

		items = append(items, listNoteItem{
			DocID:       row.DocID,
			VerID:       row.VerID,
			CreatedAt:   row.CreatedAt,
			Title:       title,
			Scope:       scope,
			BodyPreview: preview(bodyText, 120),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(listNotesResponse{Items: items})
}

func (h *NotesHandler) handleCreateNote(w http.ResponseWriter, r *http.Request) {
	var req createNoteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if _, err := uuid.Parse(req.WorkspaceID); err != nil {
		http.Error(w, "workspace_id must be a valid UUID", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Scope) == "" {
		http.Error(w, "scope is required", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Body) == "" {
		http.Error(w, "body is required", http.StatusBadRequest)
		return
	}

	workspaceDoc, err := h.store.GetLatestWorkspaceDoc(r.Context(), req.WorkspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch workspace", http.StatusInternalServerError)
		return
	}
	if workspaceDoc.DocID != req.WorkspaceID || workspaceDoc.WorkspaceID != req.WorkspaceID {
		http.NotFound(w, r)
		return
	}

	docID := uuid.NewString()
	verID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339)

	doc := map[string]any{
		"doc_type":     "memory",
		"doc_id":       docID,
		"ver_id":       verID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"body": map[string]any{
			"scope": req.Scope,
			"type":  "note",
			"content": map[string]any{
				"format": "markdown",
				"body":   req.Body,
			},
			"links": []any{},
			"provenance": map[string]any{
				"created_by": map[string]any{
					"kind": "user",
					"id":   "local",
				},
			},
		},
	}
	if strings.TrimSpace(req.Title) != "" {
		doc["meta"] = map[string]any{
			"title": req.Title,
		}
	}

	docBytes, err := json.Marshal(doc)
	if err != nil {
		http.Error(w, "failed to encode note", http.StatusInternalServerError)
		return
	}
	if err := h.validator.Validate(docBytes); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := h.store.PutDocument(r.Context(), store.Document{
		DocType:     "memory",
		DocID:       docID,
		VerID:       verID,
		WorkspaceID: req.WorkspaceID,
		CreatedAt:   createdAt,
		JSON:        string(docBytes),
	}); err != nil {
		if errors.Is(err, store.ErrDocumentExists) {
			http.Error(w, "note already exists", http.StatusConflict)
			return
		}
		http.Error(w, "failed to store note", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(createNoteResponse{
		DocID: docID,
		VerID: verID,
	})
}

func (h *NotesHandler) handleGetNote(w http.ResponseWriter, r *http.Request, docID, verID string) {
	doc, err := h.store.GetDocument(r.Context(), "memory", docID, verID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch note", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(doc.JSON))
}

func parseNotePath(path string) (docID, verID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 4 || parts[0] != "v1" || parts[1] != "notes" {
		return "", "", false
	}
	if parts[2] == "" || parts[3] == "" {
		return "", "", false
	}
	return parts[2], parts[3], true
}

func preview(text string, max int) string {
	runes := []rune(text)
	if len(runes) <= max {
		return text
	}
	return string(runes[:max])
}
