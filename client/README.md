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
  - `Workspace data root (must match server)`:
    - defaults to `../workspace-data` when running from `client/`
    - otherwise defaults to `./workspace-data`
    - settings also shows the resolved absolute path
  - `Auto-set head on save` (default `off`)

## Flow Versioning Model

- A flow identity is `doc_id`.
- Every save creates a new `ver_id`.
- **Save New Version** keeps `doc_id` and sets `parents` to `[current_ver_id]`.
- **Duplicate** creates a new `doc_id` + new `ver_id` with empty `parents`.
- **Set Head** maps workspace head for a flow `doc_id` to a specific `ver_id`.

## Node Types Registry

- The client fetches node types from the server via `GET /v1/node-types`.
- The response drives:
  - palette groups/labels
  - node input/output ports
  - inspector config fields (`string` and `bool`)
- The last successful node type set is cached locally (`SharedPreferences`).
- If fetch fails, the app falls back to cached or built-in registry and continues offline.
- Settings shows source status as `Node types: server` or `Node types: cached/fallback`.

Node config values are always written into flow JSON for forward compatibility.
Errors are selectable and include a **Copy** button for quick sharing/debugging.

## Flow Validation (Client-side)

The **Validate Flow** action checks:
- exactly one `file.read` node
- exactly one `file.write` node
- directed connectivity from `file.read` to `file.write` with all nodes on that end-to-end path
- required node config fields present (`input_file` and `output_file`)

Connection creation is also validated in-editor:
- only output -> input connections are allowed
- if both ports define schemas, schemas must match

MVP structural constraints (for example exactly one `file.read`/`file.write`) are now reported as **warnings** rather than hard errors, so you can still design multi-read/multi-write flows.

## Delete Shortcuts

- Select a node in the canvas and use **Delete node** in Inspector or press `Delete` / `Backspace` (desktop).
- Select a connection in the canvas and use **Delete connection** in Inspector or press `Delete` / `Backspace` (desktop).

## Primary Output for Multi-write Flows

- When a `file.write` node is selected, use **Set as Primary Output** in Inspector.
- The primary selection is stored in flow JSON as `node.config.primary=true` on the selected write node.
- Run output selection logic:
  - if a primary write exists, Run uses that node’s `config.output_file`
  - else if exactly one `file.write` exists, Run uses that node’s `config.output_file`
  - else Run prompts you to pick a primary write node before continuing
- Run input selection uses `file.read` `config.input_file` by default, with run-panel input field as override.

## Run Workflow

- Configure node defaults in Inspector:
  - `file.read` -> `input_file`
  - `file.write` -> `output_file`
  - for multiple writes, mark one as `primary`
- Run parameter precedence in client:
  - Run Panel value (if provided) overrides node config
  - otherwise, defaults come from node config (`file.read.input_file`, chosen `file.write.output_file`)
- If required run values are missing, the Run Panel shows inline validation and run is blocked.
- During run, the panel shows `Running...` progress.
- After run:
  - status + ids
  - output artifact summary (`path`/`bytes` when available)
  - output file path and preview (first 4k chars)
  - `Copy output` and `Open full` actions
  - on failure, trace error (`message`, `kind`, `node_id`) and invocation statuses

## Required Server Endpoints

- `POST /v1/workspaces`
- `GET /v1/workspaces/{workspace_id}/flows`
- `GET /v1/docs/flow/{doc_id}/{ver_id}`
- `PUT /v1/docs/flow/{doc_id}/{ver_id}`
- `PUT /v1/workspaces/{workspace_id}/heads/{doc_id}`
- `POST /v1/runs`
- `GET /v1/node-types`
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
   - Workspace data root (must match server) (for example `../workspace-data` when launched from `client/`)
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

Flow layout persistence:
- node positions are stored in `node.config.ui = {"x": ..., "y": ...}` on save
- on open/import, positions are restored and the canvas fits to content

## MVP Stability Checklist

- Select a workspace before Save/Run (buttons stay disabled otherwise).
- Build at least one connected graph path before Run:
  - no nodes or no edges blocks Run with guidance.
  - validation **errors** block Run (warnings do not).
- Set `file.write` primary output when multiple writes exist; Run prompts if missing.
- Keep an eye on dirty state:
  - app title shows `•` when flow has unsaved changes.
  - leaving Flow tab prompts: **Discard / Cancel / Save new version**.
- Run feedback:
  - `Running...` state with client-side **Cancel** wait.
  - completion summary includes status, duration, output path.
  - output actions: **Copy output file path**, **Copy output**, optional **Open full**.
  - failure shows trace error details and invocation statuses; transient failures expose **Retry**.

## Test

```bash
cd client
flutter test
```

## Branding

- Launcher/app icon source: `client/assets/images/cyaichi_icon_blue.png`
- Theme colors and ThemeData: `client/lib/theme/cyaichi_theme.dart`
- Regenerate launcher icons:

```bash
cd client
flutter pub run flutter_launcher_icons
```
