package httpapi

import (
	"net/http"

	"github.com/dgraham-io/cyaichi/server/internal/engine"
	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

func NewMux(
	docStore *store.Store,
	validator *schema.Validator,
	workspaceRoot string,
	vllmBaseURL string,
	vllmKey string,
	llmModel string,
	vllmTimeoutSeconds int,
) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/health", HealthHandler)
	mux.HandleFunc("/v1/node-types", NodeTypesHandler)
	if docStore != nil && validator != nil {
		nh := &NotesHandler{
			store:     docStore,
			validator: validator,
		}
		mux.HandleFunc("/v1/notes", nh.Handle)
		mux.HandleFunc("/v1/notes/", nh.Handle)

		h := &DocsHandler{
			store:     docStore,
			validator: validator,
		}
		mux.HandleFunc("/v1/docs/", h.Handle)

		wh := &WorkspacesHandler{
			store:         docStore,
			validator:     validator,
			notes:         nh,
			workspaceRoot: workspaceRoot,
		}
		mux.HandleFunc("/v1/workspaces", wh.Handle)
		mux.HandleFunc("/v1/workspaces/", wh.Handle)

		rh := &RunsHandler{
			service: engine.NewRunService(
				docStore,
				validator,
				engine.NewDefaultNodeRunner(vllmBaseURL, vllmKey, llmModel, vllmTimeoutSeconds, nil),
				workspaceRoot,
			),
		}
		mux.HandleFunc("/v1/runs", rh.Handle)

		ph := &PackagesHandler{
			service: engine.NewPackageService(docStore, validator),
			store:   docStore,
		}
		mux.HandleFunc("/v1/packages/", ph.Handle)
	}
	return mux
}
