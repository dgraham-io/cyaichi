import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';

class _WidgetTestApiClient extends ApiClient {
  _WidgetTestApiClient()
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
        configSchema: <NodeTypeConfigFieldDef>[
          NodeTypeConfigFieldDef(
            key: 'input_file',
            kind: 'string',
            required: true,
            label: 'Input file',
          ),
        ],
      ),
      NodeTypeDef(
        type: 'file.write',
        displayName: 'File Write',
        category: 'io',
        inputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'in', schema: 'artifact/text'),
        ],
        outputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'out', schema: 'artifact/output_file'),
        ],
        configSchema: <NodeTypeConfigFieldDef>[
          NodeTypeConfigFieldDef(
            key: 'output_file',
            kind: 'string',
            required: true,
            label: 'Output file',
          ),
        ],
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders canvas and adds file.read node', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _WidgetTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cyaichi'), findsOneWidget);
    expect(find.byKey(const Key('add-file.read')), findsOneWidget);
    expect(find.text('File Read 1'), findsNothing);

    await tester.tap(find.byKey(const Key('add-file.read')));
    await tester.pumpAndSettle();

    expect(find.text('File Read 1'), findsWidgets);
  });

  testWidgets('top nav group renders and switches tabs', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _WidgetTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('top-nav-group')), findsOneWidget);
    expect(find.text('Flow'), findsOneWidget);
    expect(find.text('Flows'), findsOneWidget);
    expect(find.text('Runs'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.text('Runs'));
    await tester.pumpAndSettle();

    expect(find.text('No runs found for this workspace.'), findsOneWidget);
  });

  testWidgets('node palette search filters and clear restores list', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _WidgetTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('node-palette-search-field')), findsOneWidget);
    expect(find.byKey(const Key('add-file.read')), findsOneWidget);
    expect(find.byKey(const Key('add-file.write')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('node-palette-search-field')),
      'write',
    );
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-file.read')), findsNothing);
    expect(find.byKey(const Key('add-file.write')), findsOneWidget);

    await tester.tap(find.byKey(const Key('node-palette-search-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-file.read')), findsOneWidget);
    expect(find.byKey(const Key('add-file.write')), findsOneWidget);
  });

  testWidgets('left sidebar collapses and expands', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => _WidgetTestApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebarFinder = find.byKey(const Key('left-sidebar'));
    final canvasFinder = find.byKey(const Key('flow-canvas-pane'));
    expect(sidebarFinder, findsOneWidget);
    expect(canvasFinder, findsOneWidget);
    expect(
      tester.getTopLeft(sidebarFinder).dx < tester.getTopLeft(canvasFinder).dx,
      isTrue,
    );
    expect(find.byKey(const Key('node-palette-search-field')), findsOneWidget);

    final expandedWidth = tester.getSize(sidebarFinder).width;
    await tester.tap(find.byKey(const Key('left-sidebar-collapse-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final collapsedWidth = tester.getSize(sidebarFinder).width;
    expect(collapsedWidth < expandedWidth, isTrue);
    expect(find.byKey(const Key('left-sidebar-expand-button')), findsOneWidget);
    expect(find.byKey(const Key('node-palette-search-field')), findsNothing);

    await tester.tap(find.byKey(const Key('left-sidebar-expand-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      tester.getSize(sidebarFinder).width > collapsedWidth,
      isTrue,
    );
    expect(find.byKey(const Key('node-palette-search-field')), findsOneWidget);
  });
}
