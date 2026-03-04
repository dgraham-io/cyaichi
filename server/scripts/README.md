# Demo Script

## Prerequisites

- `curl`
- `jq`
- `python3` or `uuidgen` (for UUID generation fallback)
- Running cyaichi server (`cd server && make run`)

The script uses these environment variables:

- `CYAI_BASE_URL` (default: `http://localhost:8080`)
- `CYAI_WORKSPACE_ROOT` (default: `./workspace-data`)
- `CYAI_VLLM_BASE_URL` (default: `http://192.168.1.92:8000`)
- `CYAI_LLM_MODEL` (default: `openai/gpt-oss-120b`)
- `VLLM_KEY` (required)

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
./scripts/demo.sh
```

Optional overrides:

```bash
CYAI_BASE_URL="http://localhost:8080" \
CYAI_WORKSPACE_ROOT="./workspace-data" \
CYAI_VLLM_BASE_URL="http://192.168.1.92:8000" \
CYAI_LLM_MODEL="openai/gpt-oss-120b" \
VLLM_KEY="your-real-vllm-key" \
./scripts/demo.sh
```
