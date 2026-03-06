package httpapi

import (
	"net/http"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

//go:generate go run ../../cmd/apidocgen

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
	registerRoutes(mux, &routeDeps{
		docStore:           docStore,
		validator:          validator,
		workspaceRoot:      workspaceRoot,
		vllmBaseURL:        vllmBaseURL,
		vllmKey:            vllmKey,
		llmModel:           llmModel,
		vllmTimeoutSeconds: vllmTimeoutSeconds,
	})
	return mux
}
