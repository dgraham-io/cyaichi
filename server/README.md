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
- `CYAI_DB_PATH` (default `/tmp/cyaichi.db`)
- `CYAI_WORKSPACE_ROOT` (default `./workspace-data`)
- `CYAI_VLLM_BASE_URL` (required for `llm.chat`, example `http://192.168.1.92:8000`)
- `VLLM_KEY` (required for `llm.chat`, sent as `Authorization: Bearer ...`)
- `CYAI_LLM_MODEL` (default `gpt-oss120:b`)

By default, SQLite data is created at `/tmp/cyaichi.db`.

Compatibility alias:

```bash
make server
```

## Test

```bash
cd server
make test
```

## Health check

```bash
curl -i http://127.0.0.1:8080/v1/health
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

Start server with vLLM env vars:

```bash
cd server
CYAI_VLLM_BASE_URL="http://192.168.1.92:8000" \
VLLM_KEY="replace-with-real-key" \
CYAI_LLM_MODEL="gpt-oss120:b" \
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
        {\"id\":\"n1\",\"type\":\"file.read\",\"inputs\":[],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/text\"}],\"config\":{}},
        {\"id\":\"n2\",\"type\":\"llm.chat\",\"inputs\":[{\"port\":\"in\",\"schema\":\"artifact/text\"}],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/text\"}],\"config\":{}}
      ],
      \"edges\": [
        {\"from\":{\"node\":\"n1\",\"port\":\"out\"},\"to\":{\"node\":\"n2\",\"port\":\"in\"}}
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
mkdir -p "workspace-data/$WS_ID"
printf 'hello from file.read\n' > "workspace-data/$WS_ID/input.txt"
```

Create a run:

```bash
RUN_RESP=$(curl -s -X POST http://127.0.0.1:8080/v1/runs \
  -H 'Content-Type: application/json' \
  --data-binary "{
    \"workspace_id\": \"$WS_ID\",
    \"flow_ref\": {\"doc_id\": \"$FLOW_ID\", \"ver_id\": null, \"selector\": \"head\"},
    \"inputs\": {\"input_file\": \"input.txt\", \"output_file\": \"output.txt\"}
  }")
echo "$RUN_RESP"
RUN_ID=$(echo "$RUN_RESP" | jq -r '.run_id')
RUN_VER=$(echo "$RUN_RESP" | jq -r '.run_ver_id')
```

Fetch the run document:

```bash
curl -i "http://127.0.0.1:8080/v1/docs/run/$RUN_ID/$RUN_VER"
```

Fetch the llm.chat output artifact text:

```bash
RUN_DOC=$(curl -s "http://127.0.0.1:8080/v1/docs/run/$RUN_ID/$RUN_VER")
OUT_ART_ID=$(echo "$RUN_DOC" | jq -r '.body.invocations[] | select(.node_id=="n2") | .outputs[0].artifact_ref.doc_id')
OUT_ART_VER=$(echo "$RUN_DOC" | jq -r '.body.invocations[] | select(.node_id=="n2") | .outputs[0].artifact_ref.ver_id')
curl -s "http://127.0.0.1:8080/v1/docs/artifact/$OUT_ART_ID/$OUT_ART_VER" | jq '.body.payload'
```
