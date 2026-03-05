# cyaichi server

Minimal Go HTTP server for cyaichi.

## Requirements

- Go 1.22+

## Run

```bash
cd server
make run
```

Optional environment variables:

- `CYAI_HTTP_ADDR` (default `:8080`)
- `CYAI_LOG_LEVEL` (default `info`)
- `CYAI_DB_PATH` (default `./.local/cyaichi.db`)
- `CYAI_WORKSPACE_ROOT` (default `./.local/workspace-data`)
- `CYAI_VLLM_BASE_URL` (required for `llm.chat`, example `http://192.168.1.92:8000`)
- `VLLM_KEY` (required for `llm.chat`, sent as `Authorization: Bearer ...`)
- `CYAI_LLM_MODEL` (default `openai/gpt-oss-120b`)
- `CYAI_VLLM_TIMEOUT_SECONDS` (default `120`, clamped to `5..900`)

On startup, the server creates any missing runtime directories and logs resolved absolute paths for:
- `CYAI_DB_PATH`
- `CYAI_WORKSPACE_ROOT`

For production, prefer paths under `/var/lib/cyaichi`, for example:
- `CYAI_DB_PATH=/var/lib/cyaichi/cyaichi.db`
- `CYAI_WORKSPACE_ROOT=/var/lib/cyaichi/workspace-data`

When creating a workspace, the server also creates
`{CYAI_WORKSPACE_ROOT}/{workspace_id}/`.

Compatibility alias:

```bash
make server
```

## Test

```bash
cd server
make test
```

## Demo Script

End-to-end MVP demo script:

```bash
cd server
export VLLM_KEY="your-real-vllm-key"
./scripts/demo.sh
```

Script details and prerequisites:
- [scripts/README.md](/Users/david/repos/cyaichi/server/scripts/README.md)

## Health check

```bash
curl -i http://127.0.0.1:8080/v1/health
```

## Node types

Get built-in node type templates used by the server:

```bash
curl -s http://127.0.0.1:8080/v1/node-types | jq
```

## Documents API

Store a memory document:

```bash
curl -i -X PUT http://127.0.0.1:8080/v1/docs/memory/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222 \
  -H 'Content-Type: application/json' \
  --data-binary '{
    "doc_type": "memory",
    "doc_id": "11111111-1111-1111-1111-111111111111",
    "ver_id": "22222222-2222-2222-2222-222222222222",
    "workspace_id": "33333333-3333-3333-3333-333333333333",
    "created_at": "2026-03-03T00:00:00Z",
    "body": {
      "scope": "personal",
      "type": "note",
      "content": {
        "format": "text/plain",
        "body": "hello from curl"
      },
      "provenance": {
        "created_by": {
          "kind": "user",
          "id": "demo"
        }
      }
    }
  }'
```

Fetch a document version:

```bash
curl -i http://127.0.0.1:8080/v1/docs/memory/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222
```

## Workspaces + Heads API

Create a workspace:

```bash
curl -i -X POST http://127.0.0.1:8080/v1/workspaces \
  -H 'Content-Type: application/json' \
  --data-binary '{"name":"Demo Workspace"}'
```

List workspaces (latest version per workspace, excluding soft-deleted by default):

```bash
curl -s http://127.0.0.1:8080/v1/workspaces | jq
```

Rename a workspace (creates a new workspace document version):

```bash
curl -i -X PATCH http://127.0.0.1:8080/v1/workspaces/$WS_ID \
  -H 'Content-Type: application/json' \
  --data-binary '{"name":"Renamed Workspace"}'
```

Soft-delete a workspace (creates a new version with `meta.comment=cyaichi.deleted=true`):

```bash
curl -i -X DELETE http://127.0.0.1:8080/v1/workspaces/$WS_ID
```

List including deleted workspaces:

```bash
curl -s 'http://127.0.0.1:8080/v1/workspaces?include_deleted=true' | jq
```

Set a head:

```bash
curl -i -X PUT http://127.0.0.1:8080/v1/workspaces/11111111-1111-1111-1111-111111111111/heads/44444444-4444-4444-4444-444444444444 \
  -H 'Content-Type: application/json' \
  --data-binary '{"ver_id":"55555555-5555-5555-5555-555555555555"}'
```

Get a head:

```bash
curl -i http://127.0.0.1:8080/v1/workspaces/11111111-1111-1111-1111-111111111111/heads/44444444-4444-4444-4444-444444444444
```

## Runs API

`POST /v1/runs` input/output path precedence:
- `inputs.input_file` overrides `file.read` `node.config.input_file`
- `inputs.output_file` overrides `file.write` `node.config.output_file`
- if `inputs.output_file` is omitted and multiple `file.write` nodes exist, mark exactly one with `node.config.primary=true`

`llm.chat` node config:
- `node.config.model` overrides `CYAI_LLM_MODEL` for that node
- `node.config.system_prompt` (if non-empty) is sent as a system message before the user message
- `node.config.timeout_seconds` overrides `CYAI_VLLM_TIMEOUT_SECONDS` for that node (`>0`, clamped to `5..900`)

Export environment variables:

```bash
export CYAI_DB_PATH="./.local/cyaichi.db"
export CYAI_WORKSPACE_ROOT="./.local/workspace-data"
export CYAI_VLLM_BASE_URL="http://192.168.1.92:8000"
export VLLM_KEY="replace-with-real-key"
export CYAI_LLM_MODEL="openai/gpt-oss-120b"
export CYAI_VLLM_TIMEOUT_SECONDS=120
```

Start the server:

```bash
cd server
make run
```

Create a workspace:

```bash
WS_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/workspaces \
  -H 'Content-Type: application/json' \
  --data-binary '{"name":"Run Demo"}')
echo "$WS_RESP"
WS_ID=$(echo "$WS_RESP" | jq -r '.workspace_id')
```

Put a flow document:

```bash
FLOW_ID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
FLOW_VER=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb

curl -i -X PUT "http://127.0.0.1:8080/v1/docs/flow/$FLOW_ID/$FLOW_VER" \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"doc_type\": \"flow\",
    \"doc_id\": \"$FLOW_ID\",
    \"ver_id\": \"$FLOW_VER\",
    \"workspace_id\": \"$WS_ID\",
    \"created_at\": \"2026-03-03T00:00:00Z\",
    \"body\": {
      \"nodes\": [
        {\"id\":\"n1\",\"type\":\"file.read\",\"inputs\":[],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/text\"}],\"config\":{\"input_file\":\"input.txt\"}},
        {\"id\":\"n2\",\"type\":\"llm.chat\",\"inputs\":[{\"port\":\"in\",\"schema\":\"artifact/text\"}],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/text\"}],\"config\":{\"system_prompt\":\"You are concise.\"}},
        {\"id\":\"n3\",\"type\":\"file.write\",\"inputs\":[{\"port\":\"in\",\"schema\":\"artifact/text\"}],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/output_file\"}],\"config\":{\"output_file\":\"output.txt\",\"primary\":true}}
      ],
      \"edges\": [
        {\"from\":{\"node\":\"n1\",\"port\":\"out\"},\"to\":{\"node\":\"n2\",\"port\":\"in\"}},
        {\"from\":{\"node\":\"n2\",\"port\":\"out\"},\"to\":{\"node\":\"n3\",\"port\":\"in\"}}
      ]
    }
  }"
```

Set the flow head in the workspace:

```bash
curl -i -X PUT "http://127.0.0.1:8080/v1/workspaces/$WS_ID/heads/$FLOW_ID" \
  -H 'Content-Type: application/json' \
  --data-binary "{\"ver_id\":\"$FLOW_VER\"}"
```

Write input file under the workspace root:

```bash
mkdir -p ".local/workspace-data/$WS_ID"
printf 'hello from file.read\n' > ".local/workspace-data/$WS_ID/input.txt"
```

Create a run:

```bash
RUN_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/runs \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"workspace_id\": \"$WS_ID\",
    \"flow_ref\": {\"doc_id\": \"$FLOW_ID\", \"ver_id\": null, \"selector\": \"head\"},
    \"inputs\": {}
  }")
echo "$RUN_RESP"
RUN_ID=$(echo "$RUN_RESP" | jq -r '.run_id')
RUN_VER=$(echo "$RUN_RESP" | jq -r '.run_ver_id')
```

Fetch the run document:

```bash
curl -i "http://127.0.0.1:8080/v1/docs/run/$RUN_ID/$RUN_VER"
```

Show that output file was written:

```bash
cat ".local/workspace-data/$WS_ID/output.txt"
```

Fetch the final output artifact (from `run.body.outputs[0]`):

```bash
RUN_DOC=$(curl -s "http://127.0.0.1:8080/v1/docs/run/$RUN_ID/$RUN_VER")
OUT_ART_ID=$(echo "$RUN_DOC" | jq -r '.body.outputs[0].artifact_ref.doc_id')
OUT_ART_VER=$(echo "$RUN_DOC" | jq -r '.body.outputs[0].artifact_ref.ver_id')
curl -i "http://127.0.0.1:8080/v1/docs/artifact/$OUT_ART_ID/$OUT_ART_VER"
```

## Notes API

Create workspace:

```bash
WS_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/workspaces \
  -H 'Content-Type: application/json' \
  --data-binary '{"name":"Notes Demo"}')
WS_ID=$(echo "$WS_RESP" | jq -r '.workspace_id')
echo "$WS_RESP"
```

Create note:

```bash
NOTE_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/notes \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"workspace_id\":\"$WS_ID\",
    \"scope\":\"personal\",
    \"title\":\"My first note\",
    \"body\":\"# Notes\\nThis is saved as a memory document.\"
  }")
echo "$NOTE_RESP"
NOTE_ID=$(echo "$NOTE_RESP" | jq -r '.doc_id')
NOTE_VER=$(echo "$NOTE_RESP" | jq -r '.ver_id')
```

List notes:

```bash
curl -s "http://127.0.0.1:8080/v1/workspaces/$WS_ID/notes" | jq
```

Fetch note by `doc_id` + `ver_id`:

```bash
curl -i "http://127.0.0.1:8080/v1/notes/$NOTE_ID/$NOTE_VER"
```

## Workspace List Endpoints

List flows for a workspace:

```bash
curl -s "http://127.0.0.1:8080/v1/workspaces/$WS_ID/flows" | jq
```

List runs for a workspace:

```bash
curl -s "http://127.0.0.1:8080/v1/workspaces/$WS_ID/runs" | jq
```

List notes for a workspace:

```bash
curl -s "http://127.0.0.1:8080/v1/workspaces/$WS_ID/notes" | jq
```

## Failed Run Persistence

When a run fails during execution, the server now persists a failed `run` document and returns `run_id` / `run_ver_id` in the error response.

Example (missing input file):

```bash
FAIL_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/runs \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"workspace_id\": \"$WS_ID\",
    \"flow_ref\": {\"doc_id\": \"$FLOW_ID\", \"ver_id\": null, \"selector\": \"head\"},
    \"inputs\": {\"input_file\": \"missing.txt\", \"output_file\": \"output.txt\"}
  }")
echo "$FAIL_RESP" | jq
FAIL_RUN_ID=$(echo "$FAIL_RESP" | jq -r '.run_id')
FAIL_RUN_VER=$(echo "$FAIL_RESP" | jq -r '.run_ver_id')
curl -s "http://127.0.0.1:8080/v1/docs/run/$FAIL_RUN_ID/$FAIL_RUN_VER" | jq
```

## Package Export API

Create a workspace:

```bash
WS_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/workspaces \
  -H 'Content-Type: application/json' \
  --data-binary '{"name":"Package Demo"}')
WS_ID=$(echo "$WS_RESP" | jq -r '.workspace_id')
```

Create a subflow and root flow with a subflow reference:

```bash
SUBFLOW_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
SUBFLOW_VER=$(python3 -c 'import uuid; print(uuid.uuid4())')
ROOT_FLOW_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
ROOT_FLOW_VER=$(python3 -c 'import uuid; print(uuid.uuid4())')

curl -s -X PUT "http://127.0.0.1:8080/v1/docs/flow/$SUBFLOW_ID/$SUBFLOW_VER" \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"doc_type\":\"flow\",
    \"doc_id\":\"$SUBFLOW_ID\",
    \"ver_id\":\"$SUBFLOW_VER\",
    \"workspace_id\":\"$WS_ID\",
    \"created_at\":\"2026-03-03T00:00:00Z\",
    \"body\":{\"nodes\":[],\"edges\":[]}
  }"

curl -s -X PUT "http://127.0.0.1:8080/v1/docs/flow/$ROOT_FLOW_ID/$ROOT_FLOW_VER" \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"doc_type\":\"flow\",
    \"doc_id\":\"$ROOT_FLOW_ID\",
    \"ver_id\":\"$ROOT_FLOW_VER\",
    \"workspace_id\":\"$WS_ID\",
    \"created_at\":\"2026-03-03T00:00:00Z\",
    \"body\":{
      \"nodes\":[],
      \"edges\":[],
      \"subflows\":[
        {
          \"id\":\"subflow-1\",
          \"flow_ref\":{\"doc_id\":\"$SUBFLOW_ID\",\"ver_id\":null,\"selector\":\"head\"}
        }
      ]
    }
  }"
```

Set flow heads:

```bash
curl -s -X PUT "http://127.0.0.1:8080/v1/workspaces/$WS_ID/heads/$SUBFLOW_ID" \
  -H 'Content-Type: application/json' \
  --data-binary "{\"ver_id\":\"$SUBFLOW_VER\"}"

curl -s -X PUT "http://127.0.0.1:8080/v1/workspaces/$WS_ID/heads/$ROOT_FLOW_ID" \
  -H 'Content-Type: application/json' \
  --data-binary "{\"ver_id\":\"$ROOT_FLOW_VER\"}"
```

Export a package and fetch it:

```bash
PKG_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/packages/export \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"workspace_id\":\"$WS_ID\",
    \"flow_ref\":{\"doc_id\":\"$ROOT_FLOW_ID\",\"ver_id\":null,\"selector\":\"head\"},
    \"recommended_head\":true
  }")
echo "$PKG_RESP" | jq
PKG_ID=$(echo "$PKG_RESP" | jq -r '.package_id')
PKG_VER=$(echo "$PKG_RESP" | jq -r '.package_ver_id')

curl -s "http://127.0.0.1:8080/v1/packages/$PKG_ID/$PKG_VER" | jq
```
