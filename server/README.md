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
        {\"id\":\"n1\",\"type\":\"node.in\",\"inputs\":[],\"outputs\":[{\"port\":\"out\",\"schema\":\"artifact/text\"}],\"config\":{}},
        {\"id\":\"n2\",\"type\":\"node.out\",\"inputs\":[{\"port\":\"in\",\"schema\":\"artifact/text\"}],\"outputs\":[],\"config\":{}}
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
