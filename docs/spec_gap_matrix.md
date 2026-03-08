# Spec-to-Repo Gap Matrix

This matrix maps the major sections of [the vision spec](/Users/david/repos/cyaichi/docs/cyaichi_spec.md) to the current repository state and the next concrete deliverables needed to close each gap.

## Summary

- The repo already has a credible local-first Studio prototype with versioned documents, workspace heads, runs, artifacts, collaboration records, and package export.
- The biggest Phase 1 gap is not storage. It is execution semantics and observability: the runtime is still a small synchronous validator/executor, and the client still lacks run timeline and artifact-lineage UX.
- Collaboration storage is ahead of the client product surface: channels, messages, and tasks exist on the server, but the current Activity UI is still primarily channels plus messages.

## Matrix

| Spec area | Current repo state | Concrete repo evidence | Gap to close | Planned deliverable |
| --- | --- | --- | --- | --- |
| Studio as the single visual workspace | Partial | [flow_canvas_screen.dart](/Users/david/repos/cyaichi/client/lib/src/flow_canvas_screen.dart) already provides canvas authoring, flow versioning, run launch, and right-sidebar activity | Missing dedicated run timeline, artifact provenance drill-down, and notebook-style memory surfaces | Phase 1: add timeline/details UI, provenance views, and Notebook/Records screens |
| Graph / Artifact / Run / MemoryItem conceptual model | Mostly aligned | [data_model.md](/Users/david/repos/cyaichi/docs/architecture/data_model.md), schema files in [docs/schema/v1](/Users/david/repos/cyaichi/docs/schema/v1), and append-only storage in [store](/Users/david/repos/cyaichi/server/internal/store) already model the core objects | Derived projections and retrieval indexes are still missing | Phase 1: add latest-document projections; Phase 3: add retrieval indexes |
| Workspaces and sharing | Partial | Workspace CRUD, heads, channels, messages, and tasks already exist in [workspaces.go](/Users/david/repos/cyaichi/server/internal/httpapi/workspaces.go) and [collaboration.go](/Users/david/repos/cyaichi/server/internal/httpapi/collaboration.go) | No membership model, auth, RBAC, or realtime editing/sharing controls yet | Phase 3: authentication, membership, RBAC, and collaboration policy model |
| Studio observability | Early-to-partial | Run documents and artifacts persist invocation summaries and provenance in [service.go](/Users/david/repos/cyaichi/server/internal/engine/service.go) and [runner.go](/Users/david/repos/cyaichi/server/internal/engine/runner.go) | No live graph status, no timeline, no node metrics surface, no artifact lineage UI | Phase 1: execution timeline, invocation detail views, artifact drill-down |
| Shared memory / Notebook / Records | Partial | `memory` documents already store notes plus collaboration objects; see [data_model.md](/Users/david/repos/cyaichi/docs/architecture/data_model.md) and [collaboration.md](/Users/david/repos/cyaichi/docs/architecture/collaboration.md) | Client lacks Notebook/Records UX and runtime retrieval integration | Phase 1: Notebook/Records client surface; Phase 3: retrieval-aware runtime nodes |
| Hybrid workflow engine | Early | Current runtime validates a small DAG and executes serially via [validate.go](/Users/david/repos/cyaichi/server/internal/engine/validate.go) and [service.go](/Users/david/repos/cyaichi/server/internal/engine/service.go) | No durable semantics, no retries/resume, no branching planner, no dataflow engine | Phase 1: generalized planner + minimal durable controls; Phase 2: separate durable/dataflow paths |
| Workflow paradigm breadth | Early | The flow document can already describe nodes, edges, and subflow refs, but runnable execution is intentionally narrow | Stateful cycles, fan-out/fan-in, event-heavy routing, and hybrid handoffs are not implemented | Phase 1: branching and subflow execution; Phase 2: routing, batching, and hybrid handoff semantics |
| AI Flow Builder / AI meta-layer | Not started | No prompt-to-graph or graph-diff assistant exists in the current codebase | AI suggestions would be ungrounded without better observability and retrieval | Phase 4: grounded prompt-to-graph draft generation and AI-authored diffs |
| Governance, trust, and safety | Early | Provenance is already present on artifacts and memory documents; traces are persisted as run records | No auth, approvals, policy engine, audit UI, redaction hooks, or budgets | Phase 3: policy gates, approvals, audit surfaces, cost tracking, workspace roles |
| Extensibility and openness | Partial | Processor type endpoints and package export already exist; see [endpoints.md](/Users/david/repos/cyaichi/docs/api/endpoints.md) and [package_service.go](/Users/david/repos/cyaichi/server/internal/engine/package_service.go) | No package import, no reconciliation rules, and no plugin/connector SDK | Phase 5: package import, reconciliation, connector/plugin architecture |

## Phase 0 exit alignment

Phase 0 is complete when the repo baseline is honest and green:

- Flutter narrow-width regressions are covered by tests.
- The docs state the actual shipped surface:
  - `file.monitor` is a built-in processor.
  - `Activity` is the current collaboration UI.
  - task storage exists, but task UI is still pending.
  - package export exists, but import does not.
- The remaining spec gaps are mapped to explicit follow-on phases instead of being implied loosely in the spec.
