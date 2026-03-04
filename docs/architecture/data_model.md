---

# cyaichi Architecture: Canonical Data Model & Document Format (v1)

This document is the canonical reference for how **cyaichi** represents **graphs, versions, runs, artifacts, and memory** as **JSON documents**. It is intended for both humans and AI agents implementing the platform.

## Goals

1. **Few document kinds, consistent envelope** (MVP-friendly).
2. **Strong identity + versioning** using:

   * `doc_id` (UUID): stable identity of an entity (“the graph”)
   * `ver_id` (UUID): identity of an immutable version (“that graph at this revision”)
3. **Portable & shareable** documents that can be:

   * packaged and moved across servers/environments
   * reconciled/deduped on import
4. **Graph-native references**:

   * human-friendly references (`ref`)
   * optional cross-server tracking keys (`key`)
   * graph/subworkflow references that can be pinned or floating (“use head”)

Non-goals (for this document):

* storage engine, database design, network protocols, or language/runtime choices

---

## Core Concepts

### 1) Entity Identity vs. Version Identity

* **Entity**: a conceptual thing (Graph, Prompt, Policy, Artifact, Memory Item, Run…)

  * identified by `doc_id` (UUID)
* **Version**: an immutable snapshot of an entity’s contents

  * identified by `ver_id` (UUID)
  * versions form a directed graph via `parents` (supports history, branching, merges later)

**Immutability rule**

> A JSON document identified by (`doc_id`, `ver_id`) is immutable once published.

### 2) Human Reference and Interop Key

Every document MAY include:

* **`ref`**: stable, human-friendly reference string
  Examples: `"graph:daily-triage"`, `"prompt:enrich-v2"`, `"policy:prod-safe"`
* **`key`**: optional cross-server reconciliation key
  Used when packaging/sharing to map “same logical thing” across environments.

```json
{
  "ref": "graph:daily-triage",
  "key": { "namespace": "acme.ops", "name": "daily-triage" }
}
```

Rules of thumb:

* UUIDs are canonical internally.
* `ref` is for humans/UI/logging.
* `key` is for interoperability/import reconciliation.

---

## Document Envelope (Shared Structure)

All stored JSON documents MUST follow this envelope:

```json
{
  "doc_type": "workspace | definition | run | datum | package",
  "subtype": "string-or-null",

  "doc_id": "uuid",
  "ver_id": "uuid",

  "ref": "string-optional",
  "key": { "namespace": "string", "name": "string" },

  "workspace_id": "uuid",
  "created_at": "RFC3339 timestamp",

  "parents": ["ver_id", "..."],

  "meta": {
    "title": "string-optional",
    "tags": ["string"],
    "comment": "string-optional"
  },

  "body": { }
}
```

**Required**

* `doc_type`, `doc_id`, `ver_id`, `workspace_id`, `created_at`, `body`

**Optional**

* `subtype`, `ref`, `key`, `parents`, `meta`

**Recommended (future-proof)**

* `content_hash` (e.g., sha256 of canonical JSON) for integrity/dedupe; optional in v1.

---

## Canonical Document Types (v1)

cyaichi uses a small number of document types. Most variety is represented via `subtype`.

### A) `workspace` (Container + Head Pointers + Policy Pointers)

Workspaces define boundaries for collaboration, policies, and “current version” pointers (“heads”).

```json
{
  "doc_type": "workspace",
  "doc_id": "uuid-ws",
  "ver_id": "uuid-ws-ver",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "body": {
    "name": "Acme Ops",
    "policy_refs": {
      "default_policy": { "doc_id": "uuid", "ver_id": "uuid", "selector": "pinned" }
    },
    "heads": {
      "doc_id-of-some-definition": "ver_id-of-latest",
      "doc_id-of-another": "ver_id-of-latest"
    }
  }
}
```

**Heads**

* `heads[doc_id] = ver_id` is the canonical “latest version” mapping within a workspace.
* Heads enable **floating references** (“use current head”).

---

### B) `definition` (All behavior-defining entities)

`definition` is the generic type for all “things that define behavior or configuration”.

Common subtypes include:

* `graph`
* `node_type`
* `prompt`
* `policy`
* `connector_definition` (if you choose to model connectors declaratively)

#### `definition` subtype: `graph`

```json
{
  "doc_type": "definition",
  "subtype": "graph",
  "doc_id": "uuid-graph",
  "ver_id": "uuid-graph-ver",
  "ref": "graph:daily-triage",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "parents": ["prev-ver-id"],
  "meta": { "title": "Daily Triage", "tags": ["mvp"] },
  "body": {
    "mode_hint": "durable | dataflow | hybrid",
    "nodes": [],
    "edges": [],
    "subgraphs": []
  }
}
```

**Graph shape**

* Nodes connect via edges between **ports**.
* Cycles are allowed.
* Mode hint is advisory; execution may choose differently.

##### Node

```json
{
  "id": "n1",
  "type": "ai.enrich",
  "title": "Summarize + Score",
  "inputs": [{ "port": "in", "schema": "artifact/news_item" }],
  "outputs": [{ "port": "out", "schema": "artifact/enriched_item" }],
  "config": { "prompt_ref": { "doc_id": "uuid", "ver_id": null, "selector": "head" } }
}
```

##### Edge

```json
{
  "from": { "node": "n_ingest", "port": "out" },
  "to":   { "node": "n_enrich", "port": "in" }
}
```

##### Subgraph

A subgraph is a reference to another graph definition plus optional bindings.

```json
{
  "id": "sg_notify",
  "graph_ref": { "doc_id": "uuid-subgraph", "ver_id": null, "selector": "head", "ref": "graph:notify" },
  "bindings": {
    "in": { "node": "n_gate", "port": "approved" }
  }
}
```

---

### C) `run` (Execution Record)

A `run` documents what happened when executing a graph version.

```json
{
  "doc_type": "run",
  "doc_id": "uuid-run",
  "ver_id": "uuid-run-ver",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "body": {
    "graph_ref": { "doc_id": "uuid-graph", "ver_id": "uuid-graph-ver", "selector": "pinned" },
    "mode": "durable | dataflow | hybrid",
    "status": "running | succeeded | failed | canceled",
    "started_at": "…",
    "ended_at": "…",

    "inputs": [{ "datum_ref": { "doc_id": "uuid", "ver_id": "uuid", "selector": "pinned" } }],
    "outputs": [{ "datum_ref": { "doc_id": "uuid", "ver_id": "uuid", "selector": "pinned" } }],

    "invocations": [
      {
        "invocation_id": "inv_12",
        "node_id": "n_enrich",
        "status": "succeeded",
        "started_at": "…",
        "ended_at": "…",
        "inputs": [{ "datum_ref": { "doc_id": "uuid", "ver_id": "uuid", "selector": "pinned" } }],
        "outputs": [{ "datum_ref": { "doc_id": "uuid", "ver_id": "uuid", "selector": "pinned" } }],
        "metrics": { "latency_ms": 1200, "token_in": 500, "token_out": 120 }
      }
    ],

    "trace_ref": { "kind": "optional", "id": "…" }
  }
}
```

---

### D) `datum` (Artifacts, Memory Items, Cases)

`datum` represents “stuff” produced/consumed/remembered.

Common subtypes:

* `artifact`
* `memory_item`
* (future) `case`

#### `datum` subtype: `artifact`

```json
{
  "doc_type": "datum",
  "subtype": "artifact",
  "doc_id": "uuid-artifact",
  "ver_id": "uuid-artifact-ver",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "body": {
    "schema": "artifact/enriched_item",
    "payload": { "title": "…", "score": 0.91 },
    "blob_ref": null,
    "provenance": {
      "run_ref": { "doc_id": "uuid-run", "ver_id": "uuid-run-ver", "selector": "pinned" },
      "node_id": "n_enrich",
      "derived_from": [
        { "doc_id": "uuid-prev", "ver_id": "uuid-prev-ver", "selector": "pinned" }
      ]
    }
  }
}
```

#### `datum` subtype: `memory_item`

```json
{
  "doc_type": "datum",
  "subtype": "memory_item",
  "doc_id": "uuid-mem",
  "ver_id": "uuid-mem-ver",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "body": {
    "scope": "personal | team | org | public_read",
    "type": "decision | note | procedure | …",
    "content": { "format": "markdown", "body": "…" },
    "links": [
      { "doc_id": "uuid-graph", "ver_id": null, "selector": "head", "ref": "graph:daily-triage" }
    ],
    "provenance": {
      "created_by": { "kind": "user", "id": "…" },
      "based_on": [{ "doc_id": "uuid-artifact", "ver_id": "uuid", "selector": "pinned" }]
    }
  }
}
```

---

### E) `package` (Distribution Bundle Manifest)

A package is a portable unit for export/import. It references included documents and optional blobs.

```json
{
  "doc_type": "package",
  "doc_id": "uuid-package",
  "ver_id": "uuid-package-ver",
  "workspace_id": "uuid-ws",
  "created_at": "…",
  "body": {
    "format": "cyaichi-package/v1",
    "includes": [
      { "doc_type": "definition", "doc_id": "uuid-graph", "ver_id": "uuid-graph-ver" },
      { "doc_type": "definition", "doc_id": "uuid-prompt", "ver_id": "uuid-prompt-ver" }
    ],
    "recommended_heads": [
      { "doc_id": "uuid-graph", "ver_id": "uuid-graph-ver" }
    ],
    "blobs": [
      { "blob_id": "b1", "sha256": "…", "size": 12345 }
    ]
  }
}
```

---

## Reference Objects (Graph-Native Linking)

To support graphs, subgraphs, and reusable definitions, all cross-document links MUST use a standard reference object.

### `doc_ref` (canonical)

```json
{
  "doc_id": "uuid",
  "ver_id": "uuid-or-null",
  "selector": "pinned | head",
  "ref": "optional-human-ref",
  "key": { "namespace": "optional", "name": "optional" }
}
```

Semantics:

* **Pinned reference**

  * `selector: "pinned"` and `ver_id` is set
  * Reproducible and portable
* **Floating reference (head)**

  * `selector: "head"` and `ver_id` is null
  * Resolves through workspace `heads[doc_id]`

### Resolution algorithm (normative)

Given `doc_ref` and a workspace:

1. If `selector == "pinned"`:

   * require `ver_id`
   * resolve (`doc_id`, `ver_id`)
2. If `selector == "head"`:

   * look up `ver_id = workspace.heads[doc_id]`
   * resolve (`doc_id`, `ver_id`)
3. If missing head entry:

   * treat as a resolution error (or “unresolved dependency” for packaging/import tooling)

---

## Import / Reconciliation Rules (Multi-server)

When importing a package or remote docs, the importer MAY use `key` and/or `ref` to reconcile.

### Minimal safe rule (MVP)

* If (`doc_id`, `ver_id`) exists locally: skip
* Else: store document

### Enhanced reconciliation (recommended)

If `key` is present:

* If a local entity with same `key.namespace + key.name` exists:

  * either attach imported versions into that entity’s lineage
  * or store as fork and record a mapping decision
* If no match: store as new

**Never silently rewrite `doc_id`/`ver_id`** inside imported documents. If you need remapping, do it via an import mapping table (outside this document) and keep original docs intact.

---

## MVP Implementation Checklist (Data Model)

Minimum to be compliant:

* Envelope parsing/validation for all docs
* Workspace `heads` map and `doc_ref` resolution
* Definition subtype `graph` with nodes/edges/subgraphs
* Run docs with graph pinned reference
* Datum docs for artifacts and memory items
* Package manifest for export/import (even if import is “best effort” initially)

---