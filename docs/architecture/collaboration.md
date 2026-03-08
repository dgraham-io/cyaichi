# Collaboration Architecture (MVP)

This document describes the collaboration model added on top of the existing append-only document store.

## Goals

- Support mixed chat between humans and AI agents.
- Support channels attached to a workspace, a flow, or a general topic.
- Replace the current Notes UI with a broader Activity surface.
- Keep tasks first-class instead of burying them inside chat text.
- Preserve a clean path to future AI retrieval.

## Canonical storage

The MVP keeps collaboration state in `memory` documents rather than introducing a new top-level document kind:

- `channel`: conversation container
- `message`: append-only chat event
- `task`: versioned work item

This keeps the storage model simple while preserving version history and linkage to flows, runs, and artifacts through the existing envelope and `doc_ref` patterns.

## Entity shapes

### Channel

- Belongs to a workspace.
- Uses `scope` for visibility.
- Uses `attrs.channel_kind` to distinguish `workspace`, `flow`, `topic`, and `dm`.
- May carry `attrs.flow_doc_id` / `attrs.flow_ver_id` when anchored to a flow.

### Message

- Belongs to one channel via `attrs.channel_doc_id`.
- Stores the speaker in `attrs.author`.
- Stores structured references in `attrs.refs`.
- Is append-only; edits can be modeled later as new versions if needed.

### Task

- Belongs to a workspace and may also belong to a channel.
- Stores lifecycle state in `attrs.status`.
- Stores the assignee in `attrs.assignee`.
- Stores structured references in `attrs.refs`.
- Uses normal document versioning for status transitions and future edits.

## Structured references

Messages and tasks can carry explicit refs instead of relying on text parsing alone. Current refs support:

- users
- agents
- flows
- processors
- topics

The UI currently exposes quick references for the current flow and selected processor, plus custom refs for users, agents, and topics.

## API surface

- `POST /v1/channels`
- `GET /v1/workspaces/{workspace_id}/channels`
- `POST /v1/messages`
- `GET /v1/channels/{channel_doc_id}/messages`
- `POST /v1/tasks`
- `PATCH /v1/tasks/{task_doc_id}`
- `GET /v1/workspaces/{workspace_id}/tasks`

These endpoints are intentionally polling-friendly. Realtime delivery can be layered on later without changing the storage contract.

## Client integration

The right sidebar now exposes an `Activity` panel with:

- channel creation and selection
- channel rename/delete actions
- chat timeline
- inline message composer

The old Notes sidebar is replaced by this Activity surface. Long-form notes can still be represented as messages in a dedicated channel.
Legacy note endpoints may remain temporarily for compatibility, but new product work should build on channels, messages, and tasks.

Task storage and task endpoints already exist on the server, but task list/create/update UI has not landed in the client yet. Today the Activity panel is the primary collaboration surface for channels and messages.

## Retrieval and AI path

Collaboration records should remain canonical structured data in SQLite for the MVP.

Recommended search path:

1. Store channels, messages, and tasks in SQLite.
2. Add FTS for lexical lookup.
3. Add embeddings later as a derived index over searchable chunks.
4. Return original records with source ids and refs.

That means:

- canonical state: SQLite documents + projections
- exact lookup: ids, refs, metadata filters
- text lookup: FTS
- semantic lookup: vector index

When the system outgrows SQLite, the same model can move to PostgreSQL with full-text search and `pgvector` without changing the product-level object model.
