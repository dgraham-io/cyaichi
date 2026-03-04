package httpapi

import (
	"net/http"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

func NewMux(docStore *store.Store, validator *schema.Validator) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", HealthHandler)
	if docStore != nil && validator != nil {
		h := &DocsHandler{
			store:     docStore,
			validator: validator,
		}
		mux.HandleFunc("/v1/docs/", h.Handle)

		wh := &WorkspacesHandler{
			store:     docStore,
			validator: validator,
		}
		mux.HandleFunc("/v1/workspaces", wh.Handle)
		mux.HandleFunc("/v1/workspaces/", wh.Handle)
	}
	return mux
}
