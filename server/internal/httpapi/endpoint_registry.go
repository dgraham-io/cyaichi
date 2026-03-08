package httpapi

import (
	"fmt"
	"net/http"
	"sort"
	"strings"

	"github.com/dgraham-io/cyaichi/server/internal/engine"
	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
)

// Endpoint is a single API operation documented in docs/api/endpoints.md.
type Endpoint struct {
	Area     string
	Method   string
	Path     string
	Summary  string
	Request  string
	Response string
}

type routeDeps struct {
	docStore           *store.Store
	validator          *schema.Validator
	workspaceRoot      string
	vllmBaseURL        string
	vllmKey            string
	llmModel           string
	vllmTimeoutSeconds int
	runner             engine.NodeRunner
}

type routeSpec struct {
	Pattern      string
	RequiresData bool
	HandlerKind  routeHandlerKind
	Endpoints    []Endpoint
}

type routeHandlerKind string

const (
	handlerHealth        routeHandlerKind = "health"
	handlerNodeTypes     routeHandlerKind = "node_types"
	handlerNotes         routeHandlerKind = "notes"
	handlerCollaboration routeHandlerKind = "collaboration"
	handlerDocs          routeHandlerKind = "docs"
	handlerWorkspaces    routeHandlerKind = "workspaces"
	handlerRuns          routeHandlerKind = "runs"
	handlerPackages      routeHandlerKind = "packages"
)

func buildRouteSpecs() []routeSpec {
	return []routeSpec{
		{
			Pattern:     "/v1/health",
			HandlerKind: handlerHealth,
			Endpoints: []Endpoint{
				{
					Area:     "Health",
					Method:   http.MethodGet,
					Path:     "/v1/health",
					Summary:  "Service health check.",
					Request:  "No body.",
					Response: "200 JSON { ok, service }.",
				},
			},
		},
		{
			Pattern:     "/v1/processor-types",
			HandlerKind: handlerNodeTypes,
			Endpoints: []Endpoint{
				{
					Area:     "Processor Types",
					Method:   http.MethodGet,
					Path:     "/v1/processor-types",
					Summary:  "List supported processor type definitions (preferred endpoint).",
					Request:  "No body.",
					Response: "200 JSON { items: [...] }.",
				},
			},
		},
		{
			Pattern:     "/v1/node-types",
			HandlerKind: handlerNodeTypes,
			Endpoints: []Endpoint{
				{
					Area:     "Node Types (Deprecated Alias)",
					Method:   http.MethodGet,
					Path:     "/v1/node-types",
					Summary:  "Deprecated alias for /v1/processor-types; returns identical JSON.",
					Request:  "No body.",
					Response: "200 JSON { items: [...] }.",
				},
			},
		},
		{
			Pattern:      "/v1/notes",
			RequiresData: true,
			HandlerKind:  handlerNotes,
			Endpoints: []Endpoint{
				{
					Area:     "Notes",
					Method:   http.MethodPost,
					Path:     "/v1/notes",
					Summary:  "Create a note document in a workspace.",
					Request:  "JSON: workspace_id, scope, body, optional title.",
					Response: "201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace not found.",
				},
			},
		},
		{
			Pattern:      "/v1/notes/",
			RequiresData: true,
			HandlerKind:  handlerNotes,
			Endpoints: []Endpoint{
				{
					Area:     "Notes",
					Method:   http.MethodGet,
					Path:     "/v1/notes/{doc_id}/{ver_id}",
					Summary:  "Fetch a specific note version.",
					Request:  "Path params: doc_id, ver_id.",
					Response: "200 note envelope JSON; 404 not found.",
				},
			},
		},
		{
			Pattern:      "/v1/channels",
			RequiresData: true,
			HandlerKind:  handlerCollaboration,
			Endpoints: []Endpoint{
				{
					Area:     "Collaboration",
					Method:   http.MethodPost,
					Path:     "/v1/channels",
					Summary:  "Create a workspace, flow, topic, or direct-message channel.",
					Request:  "JSON: workspace_id, scope, name, kind, optional topic/flow refs.",
					Response: "201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace not found.",
				},
			},
		},
		{
			Pattern:      "/v1/messages",
			RequiresData: true,
			HandlerKind:  handlerCollaboration,
			Endpoints: []Endpoint{
				{
					Area:     "Collaboration",
					Method:   http.MethodPost,
					Path:     "/v1/messages",
					Summary:  "Create a chat message in a channel.",
					Request:  "JSON: workspace_id, scope, channel_doc_id, body, author, optional refs.",
					Response: "201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace/channel not found.",
				},
			},
		},
		{
			Pattern:      "/v1/channels/",
			RequiresData: true,
			HandlerKind:  handlerCollaboration,
			Endpoints: []Endpoint{
				{
					Area:     "Collaboration",
					Method:   http.MethodGet,
					Path:     "/v1/channels/{channel_doc_id}/messages",
					Summary:  "List messages in a channel in timeline order.",
					Request:  "Path param: channel_doc_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, body, author_*, refs }] }.",
				},
				{
					Area:     "Collaboration",
					Method:   http.MethodPatch,
					Path:     "/v1/channels/{channel_doc_id}",
					Summary:  "Rename a channel by writing a new channel version.",
					Request:  "JSON: name.",
					Response: "200 JSON { doc_id, ver_id }; 400 invalid payload; 404 channel not found.",
				},
				{
					Area:     "Collaboration",
					Method:   http.MethodDelete,
					Path:     "/v1/channels/{channel_doc_id}",
					Summary:  "Archive a channel by writing a new archived version.",
					Request:  "No body.",
					Response: "200 JSON { doc_id, ver_id }; 404 channel not found.",
				},
			},
		},
		{
			Pattern:      "/v1/tasks",
			RequiresData: true,
			HandlerKind:  handlerCollaboration,
			Endpoints: []Endpoint{
				{
					Area:     "Collaboration",
					Method:   http.MethodPost,
					Path:     "/v1/tasks",
					Summary:  "Create a task linked to a workspace or channel.",
					Request:  "JSON: workspace_id, scope, title, body, optional channel_doc_id/assignee/refs.",
					Response: "201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace/channel not found.",
				},
			},
		},
		{
			Pattern:      "/v1/tasks/",
			RequiresData: true,
			HandlerKind:  handlerCollaboration,
			Endpoints: []Endpoint{
				{
					Area:     "Collaboration",
					Method:   http.MethodPatch,
					Path:     "/v1/tasks/{task_doc_id}",
					Summary:  "Write a new task version with updated status.",
					Request:  "JSON: status.",
					Response: "200 JSON { doc_id, ver_id }; 400 invalid payload; 404 task not found.",
				},
			},
		},
		{
			Pattern:      "/v1/docs/",
			RequiresData: true,
			HandlerKind:  handlerDocs,
			Endpoints: []Endpoint{
				{
					Area:     "Docs",
					Method:   http.MethodPut,
					Path:     "/v1/docs/{doc_type}/{doc_id}/{ver_id}",
					Summary:  "Store a validated document version.",
					Request:  "Full document JSON envelope; path/body IDs must match.",
					Response: "201 created; 400 invalid JSON/schema; 409 version exists.",
				},
				{
					Area:     "Docs",
					Method:   http.MethodGet,
					Path:     "/v1/docs/{doc_type}/{doc_id}/{ver_id}",
					Summary:  "Fetch a stored document version.",
					Request:  "Path params: doc_type, doc_id, ver_id.",
					Response: "200 document JSON; 404 not found.",
				},
			},
		},
		{
			Pattern:      "/v1/workspaces",
			RequiresData: true,
			HandlerKind:  handlerWorkspaces,
			Endpoints: []Endpoint{
				{
					Area:     "Workspaces",
					Method:   http.MethodPost,
					Path:     "/v1/workspaces",
					Summary:  "Create a workspace document and filesystem directory.",
					Request:  "JSON: name.",
					Response: "201 JSON { workspace_id, doc_id, ver_id }; 400 invalid name.",
				},
				{
					Area:     "Workspaces",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces",
					Summary:  "List latest workspace versions.",
					Request:  "Optional query: include_deleted=true|1.",
					Response: "200 JSON { items: [{ workspace_id, name, ver_id, created_at, deleted }] }.",
				},
			},
		},
		{
			Pattern:      "/v1/workspaces/",
			RequiresData: true,
			HandlerKind:  handlerWorkspaces,
			Endpoints: []Endpoint{
				{
					Area:     "Workspaces",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}",
					Summary:  "Fetch the latest workspace record.",
					Request:  "Path param: workspace_id.",
					Response: "200 workspace item JSON; 404 not found.",
				},
				{
					Area:     "Workspaces",
					Method:   http.MethodPatch,
					Path:     "/v1/workspaces/{workspace_id}",
					Summary:  "Rename a workspace by writing a new version.",
					Request:  "JSON: name.",
					Response: "200 JSON { workspace_id, ver_id, name }; 404 not found.",
				},
				{
					Area:     "Workspaces",
					Method:   http.MethodDelete,
					Path:     "/v1/workspaces/{workspace_id}",
					Summary:  "Soft-delete a workspace by writing a deleted version.",
					Request:  "No body.",
					Response: "200 JSON { workspace_id, ver_id, deleted }.",
				},
				{
					Area:     "Workspaces",
					Method:   http.MethodPut,
					Path:     "/v1/workspaces/{workspace_id}/heads/{doc_id}",
					Summary:  "Set head version for a document in a workspace.",
					Request:  "JSON: ver_id.",
					Response: "204 no content; 404 workspace/doc not found.",
				},
				{
					Area:     "Workspaces",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/heads/{doc_id}",
					Summary:  "Get current head version for a document.",
					Request:  "Path params: workspace_id, doc_id.",
					Response: "200 JSON { ver_id }; 404 if unset.",
				},
				{
					Area:     "Flows",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/flows",
					Summary:  "List latest flow versions for a workspace.",
					Request:  "Path param: workspace_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, ref, title }] }.",
				},
				{
					Area:     "Collaboration",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/channels",
					Summary:  "List latest channels for a workspace.",
					Request:  "Path param: workspace_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, name, kind, topic }] }.",
				},
				{
					Area:     "Runs",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/runs",
					Summary:  "List latest run versions for a workspace.",
					Request:  "Path param: workspace_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, status, mode }] }.",
				},
				{
					Area:     "Collaboration",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/tasks",
					Summary:  "List latest task versions for a workspace.",
					Request:  "Path param: workspace_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, title, status, assignee_label }] }.",
				},
				{
					Area:     "Notes",
					Method:   http.MethodGet,
					Path:     "/v1/workspaces/{workspace_id}/notes",
					Summary:  "List note memory docs for a workspace.",
					Request:  "Path param: workspace_id.",
					Response: "200 JSON { items: [{ doc_id, ver_id, created_at, title, scope, body_preview }] }.",
				},
			},
		},
		{
			Pattern:      "/v1/runs",
			RequiresData: true,
			HandlerKind:  handlerRuns,
			Endpoints: []Endpoint{
				{
					Area:     "Runs",
					Method:   http.MethodPost,
					Path:     "/v1/runs",
					Summary:  "Create and execute a run for the current flow head.",
					Request:  "JSON: workspace_id, flow_doc_id, input_file, output_file.",
					Response: "201 JSON run IDs and status; 400 validation; 404 missing workspace/flow; 502 upstream LLM error.",
				},
			},
		},
		{
			Pattern:      "/v1/packages/",
			RequiresData: true,
			HandlerKind:  handlerPackages,
			Endpoints: []Endpoint{
				{
					Area:     "Packages",
					Method:   http.MethodPost,
					Path:     "/v1/packages/export",
					Summary:  "Export a workspace/flow into a package document.",
					Request:  "JSON export request (workspace/flow selection + package metadata).",
					Response: "201 JSON package IDs; 400 invalid request; 404 workspace/flow not found.",
				},
				{
					Area:     "Packages",
					Method:   http.MethodGet,
					Path:     "/v1/packages/{doc_id}/{ver_id}",
					Summary:  "Fetch a stored package document.",
					Request:  "Path params: doc_id, ver_id.",
					Response: "200 package JSON; 404 not found.",
				},
			},
		},
	}
}

func collectDocumentedEndpoints() []Endpoint {
	specs := buildRouteSpecs()
	seen := map[string]struct{}{}
	endpoints := make([]Endpoint, 0, 24)
	for _, spec := range specs {
		for _, ep := range spec.Endpoints {
			key := ep.Method + " " + ep.Path
			if _, ok := seen[key]; ok {
				continue
			}
			seen[key] = struct{}{}
			endpoints = append(endpoints, ep)
		}
	}
	return endpoints
}

// DocumentedEndpoints returns every implemented endpoint that should appear in docs.
func DocumentedEndpoints() []Endpoint {
	endpoints := collectDocumentedEndpoints()
	sort.SliceStable(endpoints, func(i, j int) bool {
		if endpoints[i].Area == endpoints[j].Area {
			if endpoints[i].Path == endpoints[j].Path {
				return endpoints[i].Method < endpoints[j].Method
			}
			return endpoints[i].Path < endpoints[j].Path
		}
		return areaOrder(endpoints[i].Area) < areaOrder(endpoints[j].Area)
	})
	return endpoints
}

func areaOrder(area string) int {
	order := map[string]int{
		"Health":                        1,
		"Processor Types":               2,
		"Node Types (Deprecated Alias)": 3,
		"Workspaces":                    4,
		"Collaboration":                 5,
		"Docs":                          6,
		"Flows":                         7,
		"Runs":                          8,
		"Notes":                         9,
		"Packages":                      10,
	}
	if idx, ok := order[area]; ok {
		return idx
	}
	return 99
}

// RenderEndpointsMarkdown renders /docs/api/endpoints.md from the endpoint catalog.
func RenderEndpointsMarkdown(endpoints []Endpoint) string {
	var b strings.Builder
	b.WriteString("# API Endpoints\n\n")
	b.WriteString("Authoritative server HTTP endpoints.\n\n")
	b.WriteString("- Base URL: server-configured host (for local dev commonly `http://127.0.0.1:8080`)\n")
	b.WriteString("- Versioning: path-prefixed with `v1`\n")
	b.WriteString("- Auth: currently no authentication middleware is enforced\n\n")

	lastArea := ""
	for _, ep := range endpoints {
		if ep.Area != lastArea {
			if lastArea != "" {
				b.WriteString("\n")
			}
			lastArea = ep.Area
			b.WriteString("## " + ep.Area + "\n\n")
			b.WriteString("| Method | Path | Purpose | Request | Response |\n")
			b.WriteString("| --- | --- | --- | --- | --- |\n")
		}
		b.WriteString(fmt.Sprintf("| %s | `%s` | %s | %s | %s |\n",
			ep.Method,
			ep.Path,
			escapeTable(ep.Summary),
			escapeTable(ep.Request),
			escapeTable(ep.Response),
		))
	}
	return b.String()
}

func escapeTable(value string) string {
	return strings.ReplaceAll(value, "|", "\\|")
}

func registerRoutes(mux *http.ServeMux, deps *routeDeps) {
	handlers := map[routeHandlerKind]http.HandlerFunc{
		handlerHealth:    HealthHandler,
		handlerNodeTypes: NodeTypesHandler,
	}
	if deps.docStore != nil && deps.validator != nil {
		nh := &NotesHandler{store: deps.docStore, validator: deps.validator}
		ch := &CollaborationHandler{store: deps.docStore, validator: deps.validator}
		dh := &DocsHandler{store: deps.docStore, validator: deps.validator}
		wh := &WorkspacesHandler{store: deps.docStore, validator: deps.validator, notes: nh, collaboration: ch, workspaceRoot: deps.workspaceRoot}
		runner := deps.runner
		if runner == nil {
			runner = engine.NewDefaultNodeRunner(
				deps.vllmBaseURL,
				deps.vllmKey,
				deps.llmModel,
				deps.vllmTimeoutSeconds,
				nil,
			)
		}
		rh := &RunsHandler{
			service: engine.NewRunService(
				deps.docStore,
				deps.validator,
				runner,
				deps.workspaceRoot,
			),
		}
		ph := &PackagesHandler{
			service: engine.NewPackageService(deps.docStore, deps.validator),
			store:   deps.docStore,
		}
		handlers[handlerNotes] = nh.Handle
		handlers[handlerCollaboration] = ch.Handle
		handlers[handlerDocs] = dh.Handle
		handlers[handlerWorkspaces] = wh.Handle
		handlers[handlerRuns] = rh.Handle
		handlers[handlerPackages] = ph.Handle
	}

	for _, spec := range buildRouteSpecs() {
		if spec.RequiresData && (deps.docStore == nil || deps.validator == nil) {
			continue
		}
		handler, ok := handlers[spec.HandlerKind]
		if !ok {
			continue
		}
		mux.HandleFunc(spec.Pattern, handler)
	}
}
