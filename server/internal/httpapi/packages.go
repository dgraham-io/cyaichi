package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/dgraham-io/cyaichi/server/internal/engine"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

type PackagesHandler struct {
	service *engine.PackageService
	store   *store.Store
}

func (h *PackagesHandler) Handle(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/v1/packages/export" {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		h.handleExport(w, r)
		return
	}

	docID, verID, ok := parsePackagePath(r.URL.Path)
	if !ok {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	h.handleGet(w, r, docID, verID)
}

func (h *PackagesHandler) handleExport(w http.ResponseWriter, r *http.Request) {
	var req engine.ExportPackageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}

	resp, err := h.service.ExportPackage(r.Context(), req)
	if err != nil {
		var exportErr *engine.PackageExportError
		if errors.As(err, &exportErr) {
			http.Error(w, exportErr.Message, exportErr.StatusCode)
			return
		}
		if errors.Is(err, engine.ErrWorkspaceNotFound) || errors.Is(err, engine.ErrFlowNotFound) || errors.Is(err, engine.ErrFlowHeadNotFound) {
			http.NotFound(w, r)
			return
		}
		var validationErr *engine.ValidationError
		if errors.As(err, &validationErr) {
			http.Error(w, validationErr.Message, http.StatusBadRequest)
			return
		}
		http.Error(w, "failed to export package", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *PackagesHandler) handleGet(w http.ResponseWriter, r *http.Request, docID, verID string) {
	doc, err := h.store.GetDocument(r.Context(), "package", docID, verID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, "failed to fetch package", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(doc.JSON))
}

func parsePackagePath(path string) (docID, verID string, ok bool) {
	trimmed := strings.Trim(path, "/")
	parts := strings.Split(trimmed, "/")
	if len(parts) != 4 || parts[0] != "v1" || parts[1] != "packages" {
		return "", "", false
	}
	if parts[2] == "" || parts[3] == "" {
		return "", "", false
	}
	return parts[2], parts[3], true
}
