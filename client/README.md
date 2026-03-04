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

- Bottom navigation with four tabs:
  - **Flow**: node editor + save/run controls
  - **Flows**: flow library for list/open/version management
  - **Runs**: recent run history + run details view
  - **Notes**: notes list + create/view note
- Three-panel node editor in Flow tab:
  - left palette (`file.read`, `llm.chat`, `file.write`)
  - center pan/zoom canvas (`vyuh_node_flow`)
  - right inspector for node title + config
- Local JSON tools in Flow tab:
  - **Export JSON** (dialog + clipboard copy)
  - **Import JSON** (paste + rehydrate canvas)
- Server integration:
  - create/select workspace (workspace picker + persisted list)
  - flow library:
    - list flows in workspace
    - open flow from server into canvas
    - save **new version** (same `doc_id`, new `ver_id`, `parents=[previous_ver_id]`)
    - duplicate flow (new `doc_id`, new `ver_id`, `parents=[]`)
    - set workspace head for current flow/version
  - run flow via `/v1/runs`
  - display latest run status/error in Flow run panel
  - list recent runs in Runs tab and open details:
    - flow ref
    - invocation statuses
    - `trace_ref.error`
    - output artifact refs + output file preview
  - create/list/view notes in Notes tab
  - read and display output file contents from local filesystem
- Client settings (persisted with `SharedPreferences`):
  - `Server base URL` (default `http://localhost:8080`)
  - `Workspace data root` (default `./workspace-data`)
  - `Auto-set head on save` (default `off`)

## Flow Versioning Model

- A flow identity is `doc_id`.
- Every save creates a new `ver_id`.
- **Save New Version** keeps `doc_id` and sets `parents` to `[current_ver_id]`.
- **Duplicate** creates a new `doc_id` + new `ver_id` with empty `parents`.
- **Set Head** maps workspace head for a flow `doc_id` to a specific `ver_id`.

## Required Server Endpoints

- `POST /v1/workspaces`
- `GET /v1/workspaces/{workspace_id}/flows`
- `GET /v1/docs/flow/{doc_id}/{ver_id}`
- `PUT /v1/docs/flow/{doc_id}/{ver_id}`
- `PUT /v1/workspaces/{workspace_id}/heads/{doc_id}`
- `POST /v1/runs`
- `GET /v1/workspaces/{workspace_id}/runs`
- `GET /v1/docs/run/{doc_id}/{ver_id}`
- `GET /v1/docs/artifact/{doc_id}/{ver_id}` (for output preview in run details)
- `POST /v1/notes`
- `GET /v1/workspaces/{workspace_id}/notes`
- `GET /v1/notes/{doc_id}/{ver_id}`

## End-to-End Walkthrough

1. Start the server (`cd server && make run`).
2. Launch the Flutter app (`cd client && flutter run`).
3. Open Settings and confirm:
   - Server base URL (for example `http://localhost:8080`)
   - Workspace data root (for example `./workspace-data`)
4. Click **New Workspace**.
5. Add nodes (`file.read`, `llm.chat`, `file.write`) and connect edges.
6. Set run inputs in Run Panel (`input.txt`, `output.txt` by default).
7. Open **Flows** tab and verify the flow appears in the list.
8. Click a flow in **Flows** tab to load/re-hydrate it into the canvas.
9. In **Flow** tab:
   - click **Save New Version** to create a new `ver_id`
   - click **Duplicate** to create a new `doc_id`
   - click **Set Head** to pin workspace head to current flow version
10. Click **Run**.
11. After success, inspect:
   - run status + ids in Run Panel
   - output file contents loaded from `{workspace_data_root}/{workspace_id}/output.txt`
12. Open **Runs** tab to view run history and inspect invocation/output details.
13. Open **Notes** tab to create a note and verify it appears in list.

## Test

```bash
cd client
flutter test
```
