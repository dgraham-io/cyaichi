#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command '$1' is not installed" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq

if [ -z "${VLLM_KEY:-}" ]; then
  echo "error: VLLM_KEY is required (export VLLM_KEY before running this script)" >&2
  exit 1
fi
if [ -z "${VLLM_URL:-}" ]; then
  echo "error: VLLM_URL is required (export VLLM_URL before running this script)" >&2
  exit 1
fi

CYAI_BASE_URL="${CYAI_BASE_URL:-http://localhost:8080}"
CYAI_WORKSPACE_ROOT="${CYAI_WORKSPACE_ROOT:-./workspace-data}"
CYAI_VLLM_BASE_URL="${VLLM_URL}"
CYAI_LLM_MODEL="${CYAI_LLM_MODEL:-openai/gpt-oss-120b}"

INPUT_FILE_REL="input.txt"
OUTPUT_FILE_REL="output.txt"

api_request() {
  method="$1"
  url="$2"
  body="${3:-}"

  tmp_file="$(mktemp)"
  if [ -n "$body" ]; then
    status_code="$(curl -sS -o "$tmp_file" -w "%{http_code}" -X "$method" "$url" \
      -H 'Content-Type: application/json' \
      --data-binary "$body")"
  else
    status_code="$(curl -sS -o "$tmp_file" -w "%{http_code}" -X "$method" "$url")"
  fi

  response_body="$(cat "$tmp_file")"
  rm -f "$tmp_file"

  if [ "$status_code" -lt 200 ] || [ "$status_code" -ge 300 ]; then
    echo "error: $method $url failed with HTTP $status_code" >&2
    echo "$response_body" >&2
    exit 1
  fi

  printf '%s' "$response_body"
}

gen_uuid() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
    return
  fi
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi

  echo "error: unable to generate UUID (need python3 or uuidgen)" >&2
  exit 1
}

log_step() {
  echo
  echo "==> $1"
}

echo "Using configuration:"
echo "  CYAI_BASE_URL=$CYAI_BASE_URL"
echo "  CYAI_WORKSPACE_ROOT=$CYAI_WORKSPACE_ROOT"
echo "  CYAI_VLLM_BASE_URL=$CYAI_VLLM_BASE_URL"
echo "  CYAI_LLM_MODEL=$CYAI_LLM_MODEL"

if [[ "$CYAI_VLLM_BASE_URL" == */v1 ]]; then
  MODELS_URL="${CYAI_VLLM_BASE_URL}/models"
else
  MODELS_URL="${CYAI_VLLM_BASE_URL}/v1/models"
fi

log_step "0) Probe vLLM models"
models_tmp="$(mktemp)"
probe_status="$(curl -fsS -o "$models_tmp" -w "%{http_code}" \
  -H "Authorization: Bearer $VLLM_KEY" \
  "$MODELS_URL" || true)"
if [ "$probe_status" != "200" ]; then
  echo "error: failed to probe vLLM models at $MODELS_URL (HTTP ${probe_status:-unknown})" >&2
  if [ -s "$models_tmp" ]; then
    cat "$models_tmp" >&2
  fi
  rm -f "$models_tmp"
  exit 1
fi

models_json="$(cat "$models_tmp")"
rm -f "$models_tmp"

model_ids="$(echo "$models_json" | jq -r '.data[]?.id // empty')"
model_count="$(printf '%s\n' "$model_ids" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
if [ -z "$model_count" ] || [ "$model_count" = "0" ]; then
  echo "error: vLLM returned no models at $MODELS_URL" >&2
  echo "$models_json" >&2
  exit 1
fi

echo "available models:"
printf '%s\n' "$model_ids"

if ! printf '%s\n' "$model_ids" | grep -Fxq "$CYAI_LLM_MODEL"; then
  echo "error: configured model '$CYAI_LLM_MODEL' was not found at $MODELS_URL" >&2
  echo "available models:" >&2
  printf '%s\n' "$model_ids" >&2
  exit 1
fi

echo "vLLM OK: $model_count models found at $MODELS_URL"

log_step "1) Create workspace"
workspace_resp="$(api_request POST "$CYAI_BASE_URL/v1/workspaces" '{"name":"MVP Demo Workspace"}')"
workspace_id="$(echo "$workspace_resp" | jq -r '.workspace_id')"
if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
  echo "error: workspace_id missing in response" >&2
  echo "$workspace_resp" >&2
  exit 1
fi
echo "workspace_id=$workspace_id"

log_step "2) Write input file under workspace root"
workspace_dir="$CYAI_WORKSPACE_ROOT/$workspace_id"
mkdir -p "$workspace_dir"
printf 'Please summarize this text in one sentence.\nThis MVP runs file.read -> llm.chat -> file.write.\n' > "$workspace_dir/$INPUT_FILE_REL"
echo "wrote: $workspace_dir/$INPUT_FILE_REL"

log_step "3) Create flow document (file.read -> llm.chat -> file.write)"
flow_doc_id="$(gen_uuid)"
flow_ver_id="$(gen_uuid)"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

flow_json="$(jq -n \
  --arg flow_doc_id "$flow_doc_id" \
  --arg flow_ver_id "$flow_ver_id" \
  --arg workspace_id "$workspace_id" \
  --arg created_at "$created_at" \
  --arg llm_model "$CYAI_LLM_MODEL" \
  '{
    doc_type: "flow",
    doc_id: $flow_doc_id,
    ver_id: $flow_ver_id,
    workspace_id: $workspace_id,
    created_at: $created_at,
    body: {
      nodes: [
        {id: "n_read", type: "file.read", inputs: [], outputs: [{port: "out", schema: "artifact/text"}], config: {}},
        {id: "n_llm", type: "llm.chat", inputs: [{port: "in", schema: "artifact/text"}], outputs: [{port: "out", schema: "artifact/text"}], config: {model: $llm_model}},
        {id: "n_write", type: "file.write", inputs: [{port: "in", schema: "artifact/text"}], outputs: [{port: "out", schema: "artifact/output_file"}], config: {}}
      ],
      edges: [
        {from: {node: "n_read", port: "out"}, to: {node: "n_llm", port: "in"}},
        {from: {node: "n_llm", port: "out"}, to: {node: "n_write", port: "in"}}
      ]
    }
  }'
)"
api_request PUT "$CYAI_BASE_URL/v1/docs/flow/$flow_doc_id/$flow_ver_id" "$flow_json" >/dev/null
echo "flow stored: $flow_doc_id@$flow_ver_id"

log_step "4) Set flow head"
head_payload="$(jq -n --arg ver_id "$flow_ver_id" '{ver_id: $ver_id}')"
api_request PUT "$CYAI_BASE_URL/v1/workspaces/$workspace_id/heads/$flow_doc_id" "$head_payload" >/dev/null
echo "head set for flow $flow_doc_id"

log_step "5) Run flow"
run_payload="$(jq -n \
  --arg workspace_id "$workspace_id" \
  --arg flow_doc_id "$flow_doc_id" \
  --arg input_file "$INPUT_FILE_REL" \
  --arg output_file "$OUTPUT_FILE_REL" \
  '{
    workspace_id: $workspace_id,
    flow_ref: {doc_id: $flow_doc_id, ver_id: null, selector: "head"},
    inputs: {input_file: $input_file, output_file: $output_file}
  }'
)"
run_resp="$(api_request POST "$CYAI_BASE_URL/v1/runs" "$run_payload")"
run_doc_id="$(echo "$run_resp" | jq -r '.run_id')"
run_ver_id="$(echo "$run_resp" | jq -r '.run_ver_id')"
echo "run created: $run_doc_id@$run_ver_id"

log_step "6) Show output file + fetch run and output artifact"
output_path="$workspace_dir/$OUTPUT_FILE_REL"
if [ ! -f "$output_path" ]; then
  echo "error: output file not found: $output_path" >&2
  exit 1
fi

echo "output file: $output_path"
echo "--- output file contents ---"
cat "$output_path"
echo
echo "----------------------------"

run_doc_json="$(api_request GET "$CYAI_BASE_URL/v1/docs/run/$run_doc_id/$run_ver_id")"
out_art_doc_id="$(echo "$run_doc_json" | jq -r '.body.outputs[0].artifact_ref.doc_id')"
out_art_ver_id="$(echo "$run_doc_json" | jq -r '.body.outputs[0].artifact_ref.ver_id')"
if [ -z "$out_art_doc_id" ] || [ "$out_art_doc_id" = "null" ]; then
  echo "error: run doc did not include body.outputs[0].artifact_ref" >&2
  echo "$run_doc_json" >&2
  exit 1
fi
output_artifact_json="$(api_request GET "$CYAI_BASE_URL/v1/docs/artifact/$out_art_doc_id/$out_art_ver_id")"

echo "run doc fetched: /v1/docs/run/$run_doc_id/$run_ver_id"
echo "output artifact fetched: /v1/docs/artifact/$out_art_doc_id/$out_art_ver_id"
echo "output artifact payload:"
echo "$output_artifact_json" | jq '.body.payload'

log_step "7) Create note and list notes (if /v1/notes exists)"
note_payload="$(jq -n \
  --arg workspace_id "$workspace_id" \
  '{
    workspace_id: $workspace_id,
    scope: "personal",
    title: "Demo note",
    body: "Created by server/scripts/demo.sh"
  }'
)"

note_tmp="$(mktemp)"
note_status="$(curl -sS -o "$note_tmp" -w "%{http_code}" -X POST "$CYAI_BASE_URL/v1/notes" \
  -H 'Content-Type: application/json' \
  --data-binary "$note_payload")"
note_resp="$(cat "$note_tmp")"
rm -f "$note_tmp"

if [ "$note_status" -ge 200 ] && [ "$note_status" -lt 300 ]; then
  note_doc_id="$(echo "$note_resp" | jq -r '.doc_id')"
  note_ver_id="$(echo "$note_resp" | jq -r '.ver_id')"
  echo "note created: $note_doc_id@$note_ver_id"

  notes_list="$(api_request GET "$CYAI_BASE_URL/v1/workspaces/$workspace_id/notes")"
  echo "notes list:"
  echo "$notes_list" | jq
else
  echo "notes endpoint not available or failed (HTTP $note_status), skipping notes demo"
fi

echo
echo "Demo completed."
echo "workspace_id=$workspace_id"
echo "flow_doc_id=$flow_doc_id"
echo "flow_ver_id=$flow_ver_id"
echo "run_doc_id=$run_doc_id"
echo "run_ver_id=$run_ver_id"
echo "output_path=$output_path"
