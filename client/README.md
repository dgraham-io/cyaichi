# cyaichi client

Flutter desktop/mobile/web client for building flows and running them against the local cyaichi server.

## Run

```bash
cd server
make run
```

In another terminal:

```bash
cd client
flutter pub get
flutter run
```

## Implemented

- Three-panel node editor:
  - left palette (`file.read`, `llm.chat`, `file.write`)
  - center pan/zoom canvas (`vyuh_node_flow`)
  - right inspector for node title + config
- Local JSON tools:
  - **Export JSON** (dialog + clipboard copy)
  - **Import JSON** (paste + rehydrate canvas)
- Server integration:
  - create/select workspace
  - save flow to server as canonical `flow` doc
  - set flow head in workspace
  - run flow via `/v1/runs`
  - display run status/error
  - read and display output file contents from local filesystem
- Client settings (persisted with `SharedPreferences`):
  - `Server base URL` (default `http://localhost:8080`)
  - `Workspace data root` (default `./workspace-data`)

## End-to-End Walkthrough

1. Start the server (`cd server && make run`).
2. Launch the Flutter app (`cd client && flutter run`).
3. Open Settings and confirm:
   - Server base URL (for example `http://localhost:8080`)
   - Workspace data root (for example `./workspace-data`)
4. Click **New Workspace**.
5. Add nodes (`file.read`, `llm.chat`, `file.write`) and connect edges.
6. Set run inputs in Run Panel (`input.txt`, `output.txt` by default).
7. Click **Save to Server** (stores flow + sets head).
8. Click **Run**.
9. After success, inspect:
   - run status + ids in Run Panel
   - output file contents loaded from `{workspace_data_root}/{workspace_id}/output.txt`

## Test

```bash
cd client
flutter test
```
