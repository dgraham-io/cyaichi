package httpapi

import (
	"encoding/json"
	"net/http"
)

type healthResponse struct {
	OK      bool   `json:"ok"`
	Service string `json:"service"`
}

func HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	resp := healthResponse{
		OK:      true,
		Service: "cyaichi",
	}

	if err := json.NewEncoder(w).Encode(resp); err != nil {
		http.Error(w, "failed to encode response", http.StatusInternalServerError)
		return
	}
}
