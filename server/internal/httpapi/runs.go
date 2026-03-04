package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/dgraham-io/cyaichi/server/internal/engine"
)

type RunsHandler struct {
	service *engine.RunService
}

func (h *RunsHandler) Handle(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/v1/runs" {
		http.NotFound(w, r)
		return
	}

	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req engine.CreateRunRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}

	resp, err := h.service.CreateRun(r.Context(), req)
	if err != nil {
		var validationErr *engine.ValidationError
		if errors.As(err, &validationErr) {
			http.Error(w, validationErr.Error(), http.StatusBadRequest)
			return
		}
		if errors.Is(err, engine.ErrWorkspaceNotFound) ||
			errors.Is(err, engine.ErrFlowHeadNotFound) ||
			errors.Is(err, engine.ErrFlowNotFound) {
			http.NotFound(w, r)
			return
		}
		http.Error(w, "failed to create run", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}
