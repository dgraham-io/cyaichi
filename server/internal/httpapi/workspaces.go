package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
	"github.com/google/uuid"
)

type WorkspacesHandler struct {
	store         *store.Store
	validator     *schema.Validator
	notes         *NotesHandler
	workspaceRoot string
}

type createWorkspaceRequest struct {
	Name string `json:"name"`
}

type createWorkspaceResponse struct {
	WorkspaceID string `json:"workspace_id"`
	DocID       string `json:"doc_id"`
	VerID       string `json:"ver_id"`
}

type setHeadRequest struct {
	VerID string `json:"ver_id"`
}

type getHeadResponse struct {
	VerID string `json:"ver_id"`
}

type listFlowsResponse struct {
	Items []listFlowItem `json:"items"`
}

type listFlowItem struct {
	DocID     string `json:"doc_id"`
	VerID     string `json:"ver_id"`
	CreatedAt string `json:"created_at"`
	Ref       string `json:"ref"`
	Title     string `json:"title"`
}

type listRunsResponse struct {
	Items []listRunItem `json:"items"`
}

type listRunItem struct {
	DocID     string `json:"doc_id"`
	VerID     string `json:"ver_id"`
	CreatedAt string `json:"created_at"`
	Status    string `json:"status"`
	Mode      string `json:"mode"`
}

type listWorkspacesResponse struct {
	Items []listWorkspaceItem `json:"items"`
}

type listWorkspaceItem struct {
	WorkspaceID string `json:"workspace_id"`
	Name        string `json:"name"`
	CreatedAt   string `json:"created_at"`
}

func (h *WorkspacesHandler) Handle(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/v1/workspaces" {
		switch r.Method {
		case http.MethodPost:
			h.handleCreateWorkspace(w, r)
		case http.MethodGet:
			h.handleListWorkspaces(w, r)
		default:
			w.Header().Set("Allow", "GET, POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
		return
	}

	if workspaceID, resource, ok := parseWorkspaceListPath(r.URL.Path); ok {
		switch resource {
		case "notes":
			if h.notes == nil {
				http.NotFound(w, r)
				return
			}
			h.notes.HandleWorkspaceList(w, r, workspaceID)
		case "flows":
			h.handleListFlows(w, r, workspaceID)
		case "runs":
			h.handleListRuns(w, r, workspaceID)
		default:
			http.NotFound(w, r)
		}
		return
	}

	workspaceID, docID, ok := parseWorkspaceHeadPath(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}

	switch r.Method {
	case http.MethodPut:
		h.handleSetHead(w, r, workspaceID, docID)
	case http.MethodGet:
		h.handleGetHead(w, r, workspaceID, docID)
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *WorkspacesHandler) handleListWorkspaces(w http.ResponseWriter, r *http.Request) {
	rows, err := h.store.ListLatestDocumentsByType(r.Context(), "workspace", 100, 0)
	if err != nil {
		http.Error(w, "failed to list workspaces", http.StatusInternalServerError)
		return
	}

	items := make([]listWorkspaceItem, 0, len(rows))
	for _, row := range rows {
		name := ""
		workspaceID := row.DocID
		var doc map[string]any
		if err := json.Unmarshal([]byte(row.JSON), &doc); err == nil {
			if body, ok := doc["body"].(map[string]any); ok {
				name, _ = body["name"].(string)
			}
			if parsedWorkspaceID, ok := doc["workspace_id"].(string); ok {
				workspaceID = parsedWorkspaceID
			}
		}

		items = append(items, listWorkspaceItem{
			WorkspaceID: workspaceID,
			Name:        name,
			CreatedAt:   row.CreatedAt,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(listWorkspacesResponse{Items: items})
}

func (h *WorkspacesHandler) handleListFlows(w http.ResponseWriter, r *http.Request, workspaceID string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if _, err := h.validateWorkspace(w, r, workspaceID); err != nil {
		return
	}

	rows, err := h.store.ListDocumentsByType(r.Context(), workspaceID, "flow", 50, 0)
	if err != nil {
		http.Error(w, "failed to list flows", http.StatusInternalServerError)
		return
	}

	items := make([]listFlowItem, 0, len(rows))
	for _, row := range rows {
		title := ""
		var doc map[string]any
		if err := json.Unmarshal([]byte(row.JSON), &doc); err == nil {
			if meta, ok := doc["meta"].(map[string]any); ok {
				if parsedTitle, ok := meta["title"].(string); ok {
					title = parsedTitle
				}
			}
		}

		ref := ""
		if row.Ref.Valid {
			ref = row.Ref.String
		}

		items = append(items, listFlowItem{
			DocID:     row.DocID,
			VerID:     row.VerID,
			CreatedAt: row.CreatedAt,
			Ref:       ref,
			Title:     title,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(listFlowsResponse{Items: items})
}

func (h *WorkspacesHandler) handleListRuns(w http.ResponseWriter, r *http.Request, workspaceID string) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if _, err := h.validateWorkspace(w, r, workspaceID); err != nil {
		return
	}

	rows, err := h.store.ListDocumentsByType(r.Context(), workspaceID, "run", 50, 0)
	if err != nil {
		http.Error(w, "failed to list runs", http.StatusInternalServerError)
		return
	}

	items := make([]listRunItem, 0, len(rows))
	for _, row := range rows {
		status := ""
		mode := ""
		var doc map[string]any
		if err := json.Unmarshal([]byte(row.JSON), &doc); err == nil {
			if body, ok := doc["body"].(map[string]any); ok {
				status, _ = body["status"].(string)
				mode, _ = body["mode"].(string)
			}
		}

		items = append(items, listRunItem{
			DocID:     row.DocID,
			VerID:     row.VerID,
			CreatedAt: row.CreatedAt,
			Status:    status,
			Mode:      mode,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(listRunsResponse{Items: items})
}

func (h *WorkspacesHandler) validateWorkspace(w http.ResponseWriter, r *http.Request, workspaceID string) (store.Document, error) {
	if _, err := uuid.Parse(workspaceID); err != nil {
		http.Error(w, "workspace_id must be a valid UUID", http.StatusBadRequest)
		return store.Document{}, err
	}
	workspaceDoc, err := h.store.GetLatestWorkspaceDoc(r.Context(), workspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return store.Document{}, err
	}
	if err != nil {
		http.Error(w, "failed to fetch workspace", http.StatusInternalServerError)
		return store.Document{}, err
	}
	if workspaceDoc.DocID != workspaceID || workspaceDoc.WorkspaceID != workspaceID {
		http.NotFound(w, r)
		return store.Document{}, errors.New("workspace identity mismatch")
	}
	return workspaceDoc, nil
}

func (h *WorkspacesHandler) handleCreateWorkspace(w http.ResponseWriter, r *http.Request) {
	var req createWorkspaceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}

	workspaceID := uuid.NewString()
	verID := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)

	docJSON := map[string]any{
		"doc_type":     "workspace",
		"doc_id":       workspaceID,
		"ver_id":       verID,
		"workspace_id": workspaceID,
		"created_at":   now,
		"body": map[string]any{
			"name":  req.Name,
			"heads": map[string]string{},
		},
	}

	docBytes, err := json.Marshal(docJSON)
	if err != nil {
		http.Error(w, "failed to encode workspace document", http.StatusInternalServerError)
		return
	}

	if err := h.validator.Validate(docBytes); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := h.store.PutDocument(r.Context(), store.Document{
		DocType:     "workspace",
		DocID:       workspaceID,
		VerID:       verID,
		WorkspaceID: workspaceID,
		CreatedAt:   now,
		JSON:        string(docBytes),
	}); err != nil {
		if errors.Is(err, store.ErrDocumentExists) {
			http.Error(w, "workspace document already exists", http.StatusConflict)
			return
		}
		http.Error(w, "failed to store workspace", http.StatusInternalServerError)
		return
	}
	if strings.TrimSpace(h.workspaceRoot) != "" {
		workspaceDir := filepath.Join(h.workspaceRoot, workspaceID)
		if err := os.MkdirAll(workspaceDir, 0o755); err != nil {
			http.Error(w, "failed to create workspace directory", http.StatusInternalServerError)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(createWorkspaceResponse{
		WorkspaceID: workspaceID,
		DocID:       workspaceID,
		VerID:       verID,
	})
}

func (h *WorkspacesHandler) handleSetHead(w http.ResponseWriter, r *http.Request, workspaceID, docID string) {
	var req setHeadRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if _, err := uuid.Parse(req.VerID); err != nil {
		http.Error(w, "ver_id must be a valid UUID", http.StatusBadRequest)
		return
	}
	if _, err := uuid.Parse(workspaceID); err != nil {
		http.Error(w, "workspace_id must be a valid UUID", http.StatusBadRequest)
		return
	}
	if _, err := uuid.Parse(docID); err != nil {
		http.Error(w, "doc_id must be a valid UUID", http.StatusBadRequest)
		return
	}

	currentDoc, err := h.store.GetLatestWorkspaceDoc(r.Context(), workspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch workspace", http.StatusInternalServerError)
		return
	}
	if currentDoc.DocID != workspaceID || currentDoc.WorkspaceID != workspaceID {
		http.NotFound(w, r)
		return
	}

	var docMap map[string]any
	if err := json.Unmarshal([]byte(currentDoc.JSON), &docMap); err != nil {
		http.Error(w, "stored workspace document is invalid", http.StatusInternalServerError)
		return
	}

	bodyMap, ok := docMap["body"].(map[string]any)
	if !ok {
		http.Error(w, "stored workspace document body is invalid", http.StatusInternalServerError)
		return
	}
	headsMap, ok := bodyMap["heads"].(map[string]any)
	if !ok || headsMap == nil {
		headsMap = map[string]any{}
	}
	headsMap[docID] = req.VerID
	bodyMap["heads"] = headsMap
	docMap["body"] = bodyMap

	newWorkspaceVerID := uuid.NewString()
	docMap["ver_id"] = newWorkspaceVerID
	docMap["created_at"] = time.Now().UTC().Format(time.RFC3339)
	docMap["parents"] = []string{currentDoc.VerID}

	newDocBytes, err := json.Marshal(docMap)
	if err != nil {
		http.Error(w, "failed to encode workspace document", http.StatusInternalServerError)
		return
	}
	if err := h.validator.Validate(newDocBytes); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := h.store.PutDocument(r.Context(), store.Document{
		DocType:     "workspace",
		DocID:       workspaceID,
		VerID:       newWorkspaceVerID,
		WorkspaceID: workspaceID,
		CreatedAt:   docMap["created_at"].(string),
		JSON:        string(newDocBytes),
	}); err != nil {
		if errors.Is(err, store.ErrDocumentExists) {
			http.Error(w, "workspace document already exists", http.StatusConflict)
			return
		}
		http.Error(w, "failed to store workspace", http.StatusInternalServerError)
		return
	}

	if err := h.store.SetHead(r.Context(), workspaceID, docID, req.VerID); err != nil {
		http.Error(w, "failed to set head", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(createWorkspaceResponse{
		WorkspaceID: workspaceID,
		DocID:       workspaceID,
		VerID:       newWorkspaceVerID,
	})
}

func (h *WorkspacesHandler) handleGetHead(w http.ResponseWriter, r *http.Request, workspaceID, docID string) {
	verID, err := h.store.GetHead(r.Context(), workspaceID, docID)
	if errors.Is(err, store.ErrHeadNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch head", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(getHeadResponse{VerID: verID})
}

func parseWorkspaceHeadPath(path string) (workspaceID, docID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 5 || parts[0] != "v1" || parts[1] != "workspaces" || parts[3] != "heads" {
		return "", "", false
	}
	if parts[2] == "" || parts[4] == "" {
		return "", "", false
	}
	return parts[2], parts[4], true
}

func parseWorkspaceListPath(path string) (workspaceID, resource string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 4 || parts[0] != "v1" || parts[1] != "workspaces" {
		return "", "", false
	}
	if parts[2] == "" || parts[3] == "" {
		return "", "", false
	}
	return parts[2], parts[3], true
}
