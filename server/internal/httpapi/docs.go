package httpapi

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

type DocsHandler struct {
	store     *store.Store
	validator *schema.Validator
}

type envelopeFields struct {
	DocType     string `json:"doc_type"`
	DocID       string `json:"doc_id"`
	VerID       string `json:"ver_id"`
	WorkspaceID string `json:"workspace_id"`
	CreatedAt   string `json:"created_at"`
	Ref         string `json:"ref"`
	Key         *struct {
		Namespace string `json:"namespace"`
		Name      string `json:"name"`
	} `json:"key"`
}

func (h *DocsHandler) Handle(w http.ResponseWriter, r *http.Request) {
	docType, docID, verID, ok := parseDocPath(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}

	switch r.Method {
	case http.MethodPut:
		h.handlePut(w, r, docType, docID, verID)
	case http.MethodGet:
		h.handleGet(w, r, docType, docID, verID)
	default:
		w.Header().Set("Allow", "GET, PUT")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (h *DocsHandler) handlePut(w http.ResponseWriter, r *http.Request, docType, docID, verID string) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read request body", http.StatusBadRequest)
		return
	}

	var env envelopeFields
	if err := json.Unmarshal(body, &env); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}

	if env.DocType != docType || env.DocID != docID || env.VerID != verID {
		http.Error(w, "path and body identifiers must match", http.StatusBadRequest)
		return
	}

	if err := h.validator.Validate(body); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	doc := store.Document{
		DocType:     env.DocType,
		DocID:       env.DocID,
		VerID:       env.VerID,
		WorkspaceID: env.WorkspaceID,
		CreatedAt:   env.CreatedAt,
		JSON:        string(body),
	}
	if env.Ref != "" {
		doc.Ref = sql.NullString{String: env.Ref, Valid: true}
	}
	if env.Key != nil {
		if env.Key.Namespace != "" {
			doc.KeyNS = sql.NullString{String: env.Key.Namespace, Valid: true}
		}
		if env.Key.Name != "" {
			doc.KeyName = sql.NullString{String: env.Key.Name, Valid: true}
		}
	}

	if err := h.store.PutDocument(r.Context(), doc); err != nil {
		if errors.Is(err, store.ErrDocumentExists) {
			http.Error(w, "document version already exists", http.StatusConflict)
			return
		}
		http.Error(w, "failed to store document", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
}

func (h *DocsHandler) handleGet(w http.ResponseWriter, r *http.Request, docType, docID, verID string) {
	doc, err := h.store.GetDocument(r.Context(), docType, docID, verID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch document", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, doc.JSON)
}

func parseDocPath(path string) (docType, docID, verID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 5 || parts[0] != "v1" || parts[1] != "docs" {
		return "", "", "", false
	}
	if parts[2] == "" || parts[3] == "" || parts[4] == "" {
		return "", "", "", false
	}
	return parts[2], parts[3], parts[4], true
}
