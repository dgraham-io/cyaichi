package httpapi

import (
	"encoding/json"
	"net/http"

	"github.com/dgraham-io/cyaichi/server/internal/nodetypes"
)

type nodeTypesResponse struct {
	Items []nodetypes.NodeTypeDef `json:"items"`
}

func NodeTypesHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/v1/node-types" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(nodeTypesResponse{
		Items: nodetypes.List(),
	})
}
