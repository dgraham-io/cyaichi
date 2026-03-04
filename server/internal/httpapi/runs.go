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

type runErrorResponse struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
	RunID    string `json:"run_id,omitempty"`
	RunVerID string `json:"run_ver_id,omitempty"`
}

func writeRunError(w http.ResponseWriter, status int, message, runID, runVerID string) {
	resp := runErrorResponse{
		RunID:    runID,
		RunVerID: runVerID,
	}
	resp.Error.Message = message

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(resp)
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
		var createErr *engine.RunCreateError
		if errors.As(err, &createErr) {
			writeRunError(w, createErr.StatusCode, createErr.Message, createErr.RunID, createErr.RunVerID)
			return
		}
		var upstreamErr *engine.UpstreamError
		if errors.As(err, &upstreamErr) {
			writeRunError(w, http.StatusBadGateway, upstreamErr.Error(), "", "")
			return
		}
		var validationErr *engine.ValidationError
		if errors.As(err, &validationErr) {
			writeRunError(w, http.StatusBadRequest, validationErr.Error(), "", "")
			return
		}
		if errors.Is(err, engine.ErrWorkspaceNotFound) ||
			errors.Is(err, engine.ErrFlowHeadNotFound) ||
			errors.Is(err, engine.ErrFlowNotFound) {
			writeRunError(w, http.StatusNotFound, "not found", "", "")
			return
		}
		writeRunError(w, http.StatusInternalServerError, "failed to create run", "", "")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}
