````markdown
# cyaichi Data Model (v1)

This document is the canonical, human-readable reference for cyaichi’s JSON document model.

The normative validation rules live in `/docs/schema/v1/*.schema.json`:
- `common.schema.json`
- `envelope.schema.json`
- `workspace.schema.json`
- `flow.schema.json`
- `artifact.schema.json`
- `memory.schema.json`
- `run.schema.json`
- `package.schema.json`

---

## 1. Design goals

1. **Few document kinds** with a shared envelope.
2. **Strong identity + versioning**:
   - `doc_id` (UUID) identifies an entity (e.g., “this Flow”)
   - `ver_id` (UUID) identifies an immutable version (e.g., “this Flow at revision X”)
3. **Portability**: documents can be packaged and moved across servers/environments.
4. **Graph-native referencing**: flows/subflows and other entities can reference each other using a standard `doc_ref`, with either pinned versions or workspace “head” versions.

---

## 2. Core concepts

### 2.1 Entity vs version
- **Entity**: conceptual object (Flow, Artifact, Memory, Run, Workspace, Package)
  - identified by `doc_id`
- **Version**: immutable snapshot of an entity
  - identified by `ver_id`
  - may declare lineage via `parents: [ver_id, ...]`

**Immutability rule**
> A document identified by (`doc_id`, `ver_id`) is immutable once published.

### 2.2 Human reference and cross-server key
Documents MAY include:
- `ref`: human-friendly stable string, e.g. `flow:daily-triage`
- `key`: optional cross-server reconciliation key:
  - `{ "namespace": "acme.ops", "name": "daily-triage" }`

Rule of thumb:
- UUIDs (`doc_id`, `ver_id`) are canonical inside a server.
- `ref` is for humans/UI/logging.
- `key` is for interoperability/import reconciliation.

---

## 3. Shared document envelope

All documents share the same envelope:

```json
{
  "doc_type": "workspace | flow | run | artifact | memory | package",
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

  "content_hash": "optional string",
  "body": { }
}
````

Notes:

* `subtype` is reserved for future expansion; v1 core types typically leave it `null`.
* `content_hash` is optional and intended for integrity/dedupe later (not required for MVP).

---

## 4. Reference objects (`doc_ref`)

All cross-document links use `doc_ref`:

```json
{
  "doc_id": "uuid",
  "ver_id": "uuid-or-null",
  "selector": "pinned | head",
  "ref": "optional string",
  "key": { "namespace": "optional", "name": "optional" }
}
```

Semantics:

* **Pinned reference**: `selector: "pinned"`, `ver_id` is a UUID
  Reproducible and portable.
* **Head reference**: `selector: "head"`, `ver_id: null`
  Resolves using workspace heads.

### 4.1 Head resolution (normative)

To resolve a `doc_ref` within a workspace:

1. If `selector == "pinned"`: resolve (`doc_id`, `ver_id`) directly.
2. If `selector == "head"`: look up `ver_id = workspace.body.heads[doc_id]`, then resolve (`doc_id`, `ver_id`).
3. If missing head entry: resolution error (or “unresolved dependency” for packaging/import tooling).

---

## 5. Document types

## 5.1 Workspace (`doc_type: "workspace"`)

A workspace is the collaboration + governance container and holds the canonical **heads map**.

Body:

* `name` (required)
* `heads` (required): map of `doc_id -> ver_id`
* `policy_refs` (optional): map of name -> `doc_ref`

Example:

```json
{
  "doc_type": "workspace",
  "subtype": null,
  "doc_id": "11111111-1111-1111-1111-111111111111",
  "ver_id": "22222222-2222-2222-2222-222222222222",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T20:00:00Z",
  "body": {
    "name": "Acme Ops",
    "heads": {
      "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    },
    "policy_refs": {
      "default_policy": {
        "doc_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "ver_id": "dddddddd-dddd-dddd-dddd-dddddddddddd",
        "selector": "pinned"
      }
    }
  }
}
```

---

## 5.2 Flow (`doc_type: "flow"`)

A Flow is the versioned, visual definition of nodes, edges, and subflows.

Body:

* `mode_hint` (optional): `"durable" | "dataflow" | "hybrid"`
* `nodes` (required): array of nodes
* `edges` (required): array of edges (port-to-port connections)
* `subflows` (optional): array of subflow references + bindings

### Node shape

* `id` (string)
* `type` (string): semantic node type (executor/connector/AI/etc.)
* `title` (optional)
* `inputs`: array of `{ port, schema }`
* `outputs`: array of `{ port, schema }`
* `config`: object (intentionally open-ended in v1)

### Edge shape

* `from: { node, port }`
* `to: { node, port }`

### Subflow shape

* `id` (string)
* `flow_ref` (`doc_ref`) — may be pinned or head
* `bindings` (optional, open-ended mapping for wiring subflow boundary ports)

Example:

```json
{
  "doc_type": "flow",
  "subtype": null,
  "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  "ref": "flow:daily-triage",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T20:01:00Z",
  "parents": ["eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"],
  "meta": { "title": "Daily Triage", "tags": ["mvp"] },
  "body": {
    "mode_hint": "hybrid",
    "nodes": [
      {
        "id": "n_ingest",
        "type": "connector.ingest",
        "title": "Ingest Feeds",
        "inputs": [],
        "outputs": [{ "port": "out", "schema": "artifact/news_item" }],
        "config": { "source": "rss" }
      },
      {
        "id": "n_enrich",
        "type": "ai.enrich",
        "title": "Summarize + Score",
        "inputs": [{ "port": "in", "schema": "artifact/news_item" }],
        "outputs": [{ "port": "out", "schema": "artifact/enriched_item" }],
        "config": {
          "prompt_ref": { "doc_id": "<uuid>", "ver_id": null, "selector": "head" }
        }
      }
    ],
    "edges": [
      { "from": { "node": "n_ingest", "port": "out" }, "to": { "node": "n_enrich", "port": "in" } }
    ],
    "subflows": [
      {
        "id": "sf_notify",
        "flow_ref": { "doc_id": "ffffffff-ffff-ffff-ffff-ffffffffffff", "ver_id": null, "selector": "head", "ref": "flow:notify" },
        "bindings": { "in": { "node": "n_enrich", "port": "out" } }
      }
    ]
  }
}
```

---

## 5.3 Artifact (`doc_type: "artifact"`)

Artifacts are produced/consumed by runs and invocations. They carry optional payload and required provenance.

Body:

* `schema` (required): string identifier of artifact type
* `payload` (optional): JSON object for small payloads
* `blob_ref` (optional): external/binary payload reference (structure is intentionally open-ended in v1)
* `provenance` (required):

  * `run_ref` (`doc_ref`) pinned to the producing run version
  * `node_id` string
  * `derived_from` (optional): array of upstream artifact `doc_ref`s (usually pinned)

Example:

```json
{
  "doc_type": "artifact",
  "subtype": null,
  "doc_id": "99999999-9999-9999-9999-999999999999",
  "ver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T20:03:12Z",
  "body": {
    "schema": "artifact/enriched_item",
    "payload": { "title": "Competitor launched X", "score": 0.91 },
    "blob_ref": null,
    "provenance": {
      "run_ref": {
        "doc_id": "rrrrrrrr-rrrr-rrrr-rrrr-rrrrrrrrrrrr",
        "ver_id": "rrrrrrrr-1111-2222-3333-rrrrrrrrrrrr",
        "selector": "pinned"
      },
      "node_id": "n_enrich",
      "derived_from": [
        { "doc_id": "<uuid>", "ver_id": "<uuid>", "selector": "pinned" }
      ]
    }
  }
}
```

---

## 5.4 Memory (`doc_type: "memory"`)

Memory documents represent governed knowledge entries intended for reuse.

Body:

* `scope` (required): `"personal" | "team" | "org" | "public_read"`
* `type` (required): free-form string (e.g., `decision`, `procedure`)
* `content` (required): `{ format, body }`
* `links` (optional): array of `doc_ref` to related flows/runs/artifacts/etc.
* `provenance` (required):

  * `created_by` (open-ended object in v1)
  * `based_on` (optional): array of `doc_ref`

Example:

```json
{
  "doc_type": "memory",
  "subtype": null,
  "doc_id": "mmmmmmmm-mmmm-mmmm-mmmm-mmmmmmmmmmmm",
  "ver_id": "mmmmmmmm-1111-2222-3333-mmmmmmmmmmmm",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T20:10:00Z",
  "body": {
    "scope": "team",
    "type": "decision",
    "content": { "format": "markdown", "body": "Escalate competitor launches with score >= 0.9." },
    "links": [
      { "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "ver_id": null, "selector": "head", "ref": "flow:daily-triage" }
    ],
    "provenance": {
      "created_by": { "kind": "user", "id": "user_1" },
      "based_on": [
        { "doc_id": "99999999-9999-9999-9999-999999999999", "ver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "selector": "pinned" }
      ]
    }
  }
}
```

---

## 5.5 Run (`doc_type: "run"`)

A Run documents an execution of a specific Flow version (pinned), plus optional invocation summaries and trace pointers.

Body:

* `flow_ref` (required): `doc_ref` (should be pinned for reproducibility)
* `mode` (required): `"durable" | "dataflow" | "hybrid"`
* `status` (required): `"running" | "succeeded" | "failed" | "canceled"`
* `started_at`, `ended_at` (optional)
* `inputs` (optional): array of `{ artifact_ref: doc_ref }`
* `outputs` (optional): array of `{ artifact_ref: doc_ref }`
* `invocations` (optional): array of invocation summaries
* `trace_ref` (optional): open-ended object for deep trace storage

### Input pinning compromise (normative)

* If `mode` is `"durable"` or `"hybrid"`:

  * every `inputs[].artifact_ref` MUST be pinned (`selector:"pinned"` and UUID `ver_id`)
* If `mode` is `"dataflow"`:

  * inputs may be pinned or head (no extra restriction in v1)

Example:

```json
{
  "doc_type": "run",
  "subtype": null,
  "doc_id": "rrrrrrrr-rrrr-rrrr-rrrr-rrrrrrrrrrrr",
  "ver_id": "rrrrrrrr-1111-2222-3333-rrrrrrrrrrrr",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T20:02:00Z",
  "body": {
    "flow_ref": { "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "selector": "pinned" },
    "mode": "hybrid",
    "status": "succeeded",
    "started_at": "2026-03-03T20:02:00Z",
    "ended_at": "2026-03-03T20:05:00Z",
    "inputs": [
      {
        "artifact_ref": { "doc_id": "88888888-8888-8888-8888-888888888888", "ver_id": "77777777-7777-7777-7777-777777777777", "selector": "pinned" }
      }
    ],
    "outputs": [
      {
        "artifact_ref": { "doc_id": "99999999-9999-9999-9999-999999999999", "ver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "selector": "pinned" }
      }
    ],
    "invocations": [
      {
        "invocation_id": "inv_12",
        "node_id": "n_enrich",
        "status": "succeeded",
        "started_at": "2026-03-03T20:03:00Z",
        "ended_at": "2026-03-03T20:03:12Z",
        "inputs": [
          { "artifact_ref": { "doc_id": "88888888-8888-8888-8888-888888888888", "ver_id": "77777777-7777-7777-7777-777777777777", "selector": "pinned" } }
        ],
        "outputs": [
          { "artifact_ref": { "doc_id": "99999999-9999-9999-9999-999999999999", "ver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "selector": "pinned" } }
        ],
        "metrics": { "latency_ms": 12000, "token_in": 5000, "token_out": 800 }
      }
    ],
    "trace_ref": { "kind": "optional", "id": "trace_1" }
  }
}
```

---

## 5.6 Package (`doc_type: "package"`)

A Package is a portable distribution unit for export/import.

Body:

* `format` (required): `"cyaichi-package/v1"`
* `includes` (required): array of `{ doc_type, doc_id, ver_id }`
* `recommended_heads` (optional): array of `{ doc_id, ver_id }` for applying workspace heads after import
* `blobs` (optional): array of `{ blob_id, sha256, size }`

Example:

```json
{
  "doc_type": "package",
  "subtype": null,
  "doc_id": "pkgpkgpk-0000-0000-0000-pkgpkgpkgpkg",
  "ver_id": "pkgpkgpk-1111-2222-3333-pkgpkgpkgpkg",
  "workspace_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-03-03T21:00:00Z",
  "body": {
    "format": "cyaichi-package/v1",
    "includes": [
      { "doc_type": "flow", "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" },
      { "doc_type": "artifact", "doc_id": "99999999-9999-9999-9999-999999999999", "ver_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" },
      { "doc_type": "memory", "doc_id": "mmmmmmmm-mmmm-mmmm-mmmm-mmmmmmmmmmmm", "ver_id": "mmmmmmmm-1111-2222-3333-mmmmmmmmmmmm" }
    ],
    "recommended_heads": [
      { "doc_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "ver_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" }
    ],
    "blobs": [
      { "blob_id": "b1", "sha256": "deadbeefdeadbeefdeadbeefdeadbeef", "size": 12345 }
    ]
  }
}
```

---

## 6. Import / reconciliation guidance (non-normative but recommended)

### MVP-safe import rule

* If (`doc_id`, `ver_id`) already exists: skip
* Else: store document as-is

### Enhanced reconciliation (recommended)

If `key` exists and conflicts/duplicates are detected:

* either attach imported versions into an existing entity lineage (same `key`)
* or store as a fork and record a mapping decision

**Do not rewrite imported documents in place.** If remapping is needed, maintain a separate mapping table during import.

---