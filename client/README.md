# cyaichi client

Flutter client spike for a local node-canvas workflow editor.

## Run

```bash
cd client
flutter pub get
flutter run
```

## Implemented in this spike

- Three-panel editor layout:
  - left palette (`file.read`, `llm.chat`, `file.write`)
  - center pan/zoom canvas (`vyuh_node_flow`)
  - right inspector
- Interactive node editing:
  - select nodes
  - edit node title
  - edit config fields:
    - `file.read` -> `input_file`
    - `llm.chat` -> optional `model`
    - `file.write` -> `output_file`
- Edge creation by dragging between ports.
- Local JSON roundtrip:
  - **Export JSON** dialog + clipboard copy
  - **Import JSON** paste dialog to rehydrate graph
  - JSON shape matches flow envelope/body style used by `docs/schema/v1/flow.schema.json`
- Basic widget test: renders editor and adds a `file.read` node.

## Demo steps

1. Click `Add file.read`, `Add llm.chat`, `Add file.write`.
2. Drag from node output ports to input ports to connect.
3. Select each node and edit inspector fields.
4. Click `Export JSON` and copy output.
5. Click `Import JSON` and paste the same payload to reload.
