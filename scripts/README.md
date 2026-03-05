# Dev scripts

## reset-dev.sh

Reset local cyaichi development state (server data + local desktop client cache/config).

### Usage

Dry-run (safe preview):

```bash
CYAI_DRY_RUN=1 ./scripts/reset-dev.sh
```

CI-friendly non-interactive dry-run:

```bash
CYAI_DRY_RUN=1 CYAI_FORCE=1 ./scripts/reset-dev.sh
```

Force reset (skip confirmation):

```bash
CYAI_FORCE=1 ./scripts/reset-dev.sh
```

Normal interactive run:

```bash
./scripts/reset-dev.sh
```

### What it wipes

- Server SQLite state:
  - `CYAI_DB_PATH` (if set), plus `-wal` / `-shm`
  - `./server/.local/cyaichi.db` plus `-wal` / `-shm`
  - `/tmp/cyaichi.db` plus `-wal` / `-shm` (only when `CYAI_DB_PATH` is unset or points there)
- Server workspace/runtime directories:
  - `./server/.local/workspace-data/`
  - `./server/workspace-data/`
  - `./workspace-data/`
- macOS client cache/config (best effort):
  - `~/Library/Preferences/*cyaichi*`
  - `~/Library/Application Support/*cyaichi*`
  - `~/Library/Caches/*cyaichi*`
  - plus bundle-id-based matches when detected from the Flutter macOS project

The script prints each resolved path before deletion and skips missing paths quietly.

### Notes

- The script is intentionally defensive and refuses suspicious targets.
- For iOS/Android simulator/device testing, resetting may also require uninstalling the app or clearing app data.
