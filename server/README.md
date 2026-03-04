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
