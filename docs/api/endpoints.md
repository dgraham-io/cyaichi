# API Endpoints

Authoritative server HTTP endpoints.

- Base URL: server-configured host (for local dev commonly `http://127.0.0.1:8080`)
- Versioning: path-prefixed with `v1`
- Auth: currently no authentication middleware is enforced

## Health

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/health` | Service health check. | No body. | 200 JSON { ok, service }. |

## Processor Types

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/processor-types` | List supported processor type definitions (preferred endpoint). | No body. | 200 JSON { items: [...] }. |

## Node Types (Deprecated Alias)

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/node-types` | Deprecated alias for /v1/processor-types; returns identical JSON. | No body. | 200 JSON { items: [...] }. |

## Workspaces

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/workspaces` | List latest workspace versions. | Optional query: include_deleted=true\|1. | 200 JSON { items: [{ workspace_id, name, ver_id, created_at, deleted }] }. |
| POST | `/v1/workspaces` | Create a workspace document and filesystem directory. | JSON: name. | 201 JSON { workspace_id, doc_id, ver_id }; 400 invalid name. |
| DELETE | `/v1/workspaces/{workspace_id}` | Soft-delete a workspace by writing a deleted version. | No body. | 200 JSON { workspace_id, ver_id, deleted }. |
| GET | `/v1/workspaces/{workspace_id}` | Fetch the latest workspace record. | Path param: workspace_id. | 200 workspace item JSON; 404 not found. |
| PATCH | `/v1/workspaces/{workspace_id}` | Rename a workspace by writing a new version. | JSON: name. | 200 JSON { workspace_id, ver_id, name }; 404 not found. |
| GET | `/v1/workspaces/{workspace_id}/heads/{doc_id}` | Get current head version for a document. | Path params: workspace_id, doc_id. | 200 JSON { ver_id }; 404 if unset. |
| PUT | `/v1/workspaces/{workspace_id}/heads/{doc_id}` | Set head version for a document in a workspace. | JSON: ver_id. | 204 no content; 404 workspace/doc not found. |

## Collaboration

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| POST | `/v1/channels` | Create a workspace, flow, topic, or direct-message channel. | JSON: workspace_id, scope, name, kind, optional topic/flow refs. | 201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace not found. |
| DELETE | `/v1/channels/{channel_doc_id}` | Archive a channel by writing a new archived version. | No body. | 200 JSON { doc_id, ver_id }; 404 channel not found. |
| PATCH | `/v1/channels/{channel_doc_id}` | Rename a channel by writing a new channel version. | JSON: name. | 200 JSON { doc_id, ver_id }; 400 invalid payload; 404 channel not found. |
| GET | `/v1/channels/{channel_doc_id}/messages` | List messages in a channel in timeline order. | Path param: channel_doc_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, body, author_*, refs }] }. |
| POST | `/v1/messages` | Create a chat message in a channel. | JSON: workspace_id, scope, channel_doc_id, body, author, optional refs. | 201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace/channel not found. |
| POST | `/v1/tasks` | Create a task linked to a workspace or channel. | JSON: workspace_id, scope, title, body, optional channel_doc_id/assignee/refs. | 201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace/channel not found. |
| PATCH | `/v1/tasks/{task_doc_id}` | Write a new task version with updated status. | JSON: status. | 200 JSON { doc_id, ver_id }; 400 invalid payload; 404 task not found. |
| GET | `/v1/workspaces/{workspace_id}/channels` | List latest channels for a workspace. | Path param: workspace_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, name, kind, topic }] }. |
| GET | `/v1/workspaces/{workspace_id}/tasks` | List latest task versions for a workspace. | Path param: workspace_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, title, status, assignee_label }] }. |

## Docs

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/docs/{doc_type}/{doc_id}/{ver_id}` | Fetch a stored document version. | Path params: doc_type, doc_id, ver_id. | 200 document JSON; 404 not found. |
| PUT | `/v1/docs/{doc_type}/{doc_id}/{ver_id}` | Store a validated document version. | Full document JSON envelope; path/body IDs must match. | 201 created; 400 invalid JSON/schema; 409 version exists. |

## Flows

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| GET | `/v1/workspaces/{workspace_id}/flows` | List latest flow versions for a workspace. | Path param: workspace_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, ref, title }] }. |

## Runs

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| POST | `/v1/runs` | Create and execute a run for the current flow head. | JSON: workspace_id, flow_doc_id, input_file, output_file. | 201 JSON run IDs and status; 400 validation; 404 missing workspace/flow; 502 upstream LLM error. |
| GET | `/v1/workspaces/{workspace_id}/runs` | List latest run versions for a workspace. | Path param: workspace_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, status, mode }] }. |

## Notes

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| POST | `/v1/notes` | Create a note document in a workspace. | JSON: workspace_id, scope, body, optional title. | 201 JSON { doc_id, ver_id }; 400 invalid payload; 404 workspace not found. |
| GET | `/v1/notes/{doc_id}/{ver_id}` | Fetch a specific note version. | Path params: doc_id, ver_id. | 200 note envelope JSON; 404 not found. |
| GET | `/v1/workspaces/{workspace_id}/notes` | List note memory docs for a workspace. | Path param: workspace_id. | 200 JSON { items: [{ doc_id, ver_id, created_at, title, scope, body_preview }] }. |

## Packages

| Method | Path | Purpose | Request | Response |
| --- | --- | --- | --- | --- |
| POST | `/v1/packages/export` | Export a workspace/flow into a package document. | JSON export request (workspace/flow selection + package metadata). | 201 JSON package IDs; 400 invalid request; 404 workspace/flow not found. |
| GET | `/v1/packages/{doc_id}/{ver_id}` | Fetch a stored package document. | Path params: doc_id, ver_id. | 200 package JSON; 404 not found. |
