# Demo Script

## Prerequisites

- `curl`
- `jq`
- `python3` or `uuidgen` (for UUID generation fallback)
- Running cyaichi server (`cd server && make run`)

The script uses these environment variables:

- `CYAI_BASE_URL` (default: `http://localhost:8080`)
- `CYAI_WORKSPACE_ROOT` (default: `./workspace-data`)
- `VLLM_URL` (required; OpenAI-compatible vLLM base URL)
- `CYAI_LLM_MODEL` (optional; defaults to the script's built-in value)
- `VLLM_KEY` (required)

Before running the flow, the script probes `GET ${VLLM_URL}/v1/models` (or `${VLLM_URL}/models` when `VLLM_URL` already ends with `/v1`), prints available model IDs, and exits if `CYAI_LLM_MODEL` is not present.

## Run

In one terminal:

```bash
cd server
make run
```

In another terminal:

```bash
cd server
export VLLM_KEY="your-real-vllm-key"
export VLLM_URL="http://your-vllm-host:8000"
./scripts/demo.sh
```

Optional overrides:

```bash
CYAI_BASE_URL="http://localhost:8080" \
CYAI_WORKSPACE_ROOT="./workspace-data" \
VLLM_URL="http://your-vllm-host:8000" \
CYAI_LLM_MODEL="your-model-id" \
VLLM_KEY="your-real-vllm-key" \
./scripts/demo.sh
```
