import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

class _FlowTitleTestApiClient extends ApiClient {
  _FlowTitleTestApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  @override
  void close() {}

  @override
  Future<List<WorkspaceListItem>> getWorkspaces() async {
    return <WorkspaceListItem>[
      WorkspaceListItem(
        workspaceId: '11111111-1111-1111-1111-111111111111',
        name: 'Workspace One',
        createdAt: '2026-03-05T00:00:00Z',
      ),
    ];
  }

  @override
  Future<List<NodeTypeDef>> getNodeTypes() async {
    return <NodeTypeDef>[
      NodeTypeDef(
        type: 'file.read',
        displayName: 'File Read',
        category: 'io',
        inputs: const <NodeTypePortDef>[],
        outputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'out', schema: 'artifact/text'),
        ],
        configSchema: const <NodeTypeConfigFieldDef>[],
      ),
    ];
  }

  @override
  Future<List<FlowListItem>> getFlows({required String workspaceId}) async {
    return const <FlowListItem>[];
  }

  @override
  Future<List<RunListItem>> getRuns({required String workspaceId}) async {
    return const <RunListItem>[];
  }

  @override
  Future<List<NoteListItem>> getNotes({required String workspaceId}) async {
    return const <NoteListItem>[];
  }
}

class _RunValidApiClient extends ApiClient {
  _RunValidApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  @override
  void close() {}

  @override
  Future<List<WorkspaceListItem>> getWorkspaces() async {
    return <WorkspaceListItem>[
      WorkspaceListItem(
        workspaceId: '11111111-1111-1111-1111-111111111111',
        name: 'Workspace One',
        createdAt: '2026-03-05T00:00:00Z',
      ),
    ];
  }

  @override
  Future<List<NodeTypeDef>> getNodeTypes() async {
    return <NodeTypeDef>[
      NodeTypeDef(
        type: 'source.node',
        displayName: 'Source',
        category: 'custom',
        inputs: const <NodeTypePortDef>[],
        outputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'out', schema: 'artifact/text'),
        ],
        configSchema: const <NodeTypeConfigFieldDef>[],
      ),
      NodeTypeDef(
        type: 'sink.node',
        displayName: 'Sink',
        category: 'custom',
        inputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'in', schema: 'artifact/text'),
        ],
        outputs: const <NodeTypePortDef>[],
        configSchema: const <NodeTypeConfigFieldDef>[],
      ),
    ];
  }

  @override
  Future<List<FlowListItem>> getFlows({required String workspaceId}) async {
    return const <FlowListItem>[];
  }

  @override
  Future<List<RunListItem>> getRuns({required String workspaceId}) async {
    return const <RunListItem>[];
  }

  @override
  Future<List<NoteListItem>> getNotes({required String workspaceId}) async {
    return const <NoteListItem>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
  });

  testWidgets('rename flow action updates title and marks flow dirty', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flow-title-overlay')), findsOneWidget);
    expect(find.byKey(const Key('flow-title-display')), findsOneWidget);
    expect(find.byKey(const Key('flow-title-actions-button')), findsOneWidget);
    expect(find.text('My Flow'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);

    await tester.tap(find.byKey(const Key('flow-title-actions-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('flow-title-edit-menu-rename')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('flow-title-edit-menu-rename')));
    await tester.pumpAndSettle();

    expect(find.text('Rename flow'), findsOneWidget);
    final renameField = find.byType(TextFormField);
    expect(renameField, findsOneWidget);
    await tester.enterText(renameField, 'Renamed Flow');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed Flow'), findsOneWidget);
    expect(find.textContaining('•'), findsOneWidget);
  });

  testWidgets(
    'flow title overlay has one actions icon and menu includes Rename flow',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: FlowCanvasScreen(
            apiClientFactory:
                ({
                  required String baseUrl,
                  required int runRequestTimeoutSeconds,
                }) => _FlowTitleTestApiClient(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('flow-title-actions-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('flow-title-actions-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('flow-title-edit-menu-rename')),
        findsOneWidget,
      );
      expect(find.text('Rename flow'), findsOneWidget);
    },
  );

  testWidgets('edit menu shows update, duplicate, and set head actions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('flow-title-actions-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('flow-title-edit-menu-update')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('flow-title-edit-menu-duplicate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('flow-title-edit-menu-set-head')),
      findsOneWidget,
    );

    final updateItem = tester.widget<MenuItemButton>(
      find.byKey(const Key('flow-title-edit-menu-update')),
    );
    expect(updateItem.onPressed, isNull);
  });

  testWidgets('flow overlay contains run button and divider', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flow-title-overlay')), findsOneWidget);
    expect(find.byKey(const Key('flow-title-actions-button')), findsOneWidget);
    expect(find.byKey(const Key('flow-title-run-divider')), findsOneWidget);
    expect(find.byKey(const Key('flow-title-run-button')), findsOneWidget);

    final runTooltip = tester.widget<Tooltip>(
      find.byKey(const Key('flow-title-run-tooltip')),
    );
    expect(runTooltip.message, startsWith('Run'));
  });

  testWidgets('floating toolbar run is disabled with no workspace selected', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final runButton = tester.widget<IconButton>(
      find.byKey(const Key('flow-title-run-button')),
    );
    expect(runButton.onPressed, isNull);

    final runTooltip = tester.widget<Tooltip>(
      find.byKey(const Key('flow-title-run-tooltip')),
    );
    expect(runTooltip.message, 'Run (select a workspace)');
  });

  testWidgets('invalid flow shows blocked run overlay and disabled button', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final runButton = tester.widget<IconButton>(
      find.byKey(const Key('flow-title-run-button')),
    );
    expect(runButton.onPressed, isNull);
    expect(
      find.byKey(const Key('flow-title-run-blocked-overlay')),
      findsOneWidget,
    );
  });

  testWidgets('valid flow enables run and hides blocked overlay', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _RunValidApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(FlowCanvasScreen));
    state.debugSetSimpleGraphForTest(
      nodes: <Node<Map<String, dynamic>>>[
        Node<Map<String, dynamic>>(
          id: 'source-1',
          type: 'source.node',
          position: const Offset(100, 120),
          size: const Size(220, 132),
          ports: <Port>[
            Port(
              id: 'out',
              name: 'out',
              position: PortPosition.right,
              type: PortType.output,
              offset: Offset(0, 66),
              multiConnections: true,
            ),
          ],
          data: <String, dynamic>{
            'title': 'Source',
            'config': <String, dynamic>{},
            'inputs': <Map<String, dynamic>>[],
            'outputs': <Map<String, dynamic>>[
              <String, dynamic>{'port': 'out', 'schema': 'artifact/text'},
            ],
          },
        ),
        Node<Map<String, dynamic>>(
          id: 'sink-1',
          type: 'sink.node',
          position: const Offset(420, 120),
          size: const Size(220, 132),
          ports: <Port>[
            Port(
              id: 'in',
              name: 'in',
              position: PortPosition.left,
              type: PortType.input,
              offset: Offset(0, 66),
              multiConnections: true,
            ),
          ],
          data: <String, dynamic>{
            'title': 'Sink',
            'config': <String, dynamic>{},
            'inputs': <Map<String, dynamic>>[
              <String, dynamic>{'port': 'in', 'schema': 'artifact/text'},
            ],
            'outputs': <Map<String, dynamic>>[],
          },
        ),
      ],
      connections: <Connection<dynamic>>[
        Connection<dynamic>(
          id: 'conn-1',
          sourceNodeId: 'source-1',
          sourcePortId: 'out',
          targetNodeId: 'sink-1',
          targetPortId: 'in',
        ),
      ],
    );
    await tester.pumpAndSettle();

    final runButton = tester.widget<IconButton>(
      find.byKey(const Key('flow-title-run-button')),
    );
    expect(runButton.onPressed, isNotNull);
    expect(
      find.byKey(const Key('flow-title-run-blocked-overlay')),
      findsNothing,
    );
  });

  testWidgets('zoom panel renders with zoom icons', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _FlowTitleTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('canvas-zoom-toolbar')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('canvas-zoom-toolbar')),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('canvas-zoom-toolbar')),
        matching: find.byIcon(Icons.remove),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('canvas-zoom-toolbar')),
        matching: find.byIcon(Icons.center_focus_strong_outlined),
      ),
      findsOneWidget,
    );
  });
}
