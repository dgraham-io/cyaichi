# cyaichi

Open-source local-first flow execution prototype with Go server and Flutter client.

- Server: [`server/`](server/)
- Client: [`client/`](client/)
- Architecture/docs: [`docs/`](docs/)

## Current Product Surface

- Studio canvas for authoring flows, importing/exporting JSON, versioning flows, and launching runs.
- Built-in processors: `file.read`, `file.write`, `file.monitor`, and `llm.chat`.
- The primary collaboration surface in the client is the `Activity` sidebar for channels and messages.
- Task endpoints exist on the server, but task workflow UI is not yet shipped in the client.
- Package export exists on the server; package import and reconciliation are not implemented yet.

## Development reset script

To wipe local development state (SQLite DBs, workspace data, and local client cache/config), use:

```bash
CYAI_DRY_RUN=1 ./scripts/reset-dev.sh
```

```bash
CYAI_FORCE=1 ./scripts/reset-dev.sh
```

See [`scripts/README.md`](scripts/README.md) for full details.
