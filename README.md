# cyaichi

Open-source local-first flow execution prototype with Go server and Flutter client.

- Server: [`server/`](server/)
- Client: [`client/`](client/)
- Architecture/docs: [`docs/`](docs/)

## Development reset script

To wipe local development state (SQLite DBs, workspace data, and local client cache/config), use:

```bash
CYAI_DRY_RUN=1 ./scripts/reset-dev.sh
```

```bash
CYAI_FORCE=1 ./scripts/reset-dev.sh
```

See [`scripts/README.md`](scripts/README.md) for full details.
