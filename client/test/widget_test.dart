import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/api/api_client.dart';
import 'package:client/messages/message_center.dart';
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
    MessageCenter.instance.clear();
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

    expect(find.byKey(const Key('workspace-title-row')), findsOneWidget);
    expect(find.byKey(const Key('add-file.read')), findsOneWidget);
    expect(find.text('File Read 1'), findsNothing);

    await tester.tap(find.byKey(const Key('add-file.read')));
    await tester.pumpAndSettle();

    expect(find.text('File Read 1'), findsWidgets);
  });

  testWidgets('top nav group renders without flows/runs and switches tabs', (
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
    final topNavFinder = find.byKey(const Key('top-nav-group'));
    expect(
      find.descendant(of: topNavFinder, matching: find.text('Flow')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: topNavFinder, matching: find.text('Flows')),
      findsNothing,
    );
    expect(
      find.descendant(of: topNavFinder, matching: find.text('Runs')),
      findsNothing,
    );
    expect(
      find.descendant(of: topNavFinder, matching: find.text('Notes')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: topNavFinder, matching: find.text('Notes')),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notes found for this workspace.'), findsOneWidget);
  });

  testWidgets('app bar shows workspace section on left and new flow button', (
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

    expect(find.byKey(const Key('workspace-title-row')), findsOneWidget);
    expect(find.byKey(const Key('workspace-actions-button')), findsOneWidget);
    expect(find.byKey(const Key('new-flow-button')), findsOneWidget);
    expect(find.text('My Flow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-flow-button')));
    await tester.pumpAndSettle();

    expect(find.text('Untitled Flow'), findsOneWidget);
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

  testWidgets('right overlay sidebar toggles without resizing canvas', (
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

    final sidebarFinder = find.byKey(const Key('right-overlay-sidebar'));
    final canvasFinder = find.byKey(const Key('flow-canvas-pane'));
    expect(sidebarFinder, findsOneWidget);
    expect(canvasFinder, findsOneWidget);
    expect(
      find.byKey(const Key('right-sidebar-resize-handle-hit')),
      findsOneWidget,
    );

    final canvasRectBefore = tester.getRect(canvasFinder);
    expect(find.byKey(const Key('node-palette-search-field')), findsOneWidget);
    expect(
      tester.getTopLeft(sidebarFinder).dx < canvasRectBefore.right,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('right-sidebar-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final canvasRectClosed = tester.getRect(canvasFinder);
    expect(canvasRectClosed, equals(canvasRectBefore));
    expect(
      tester.getTopLeft(sidebarFinder).dx >= canvasRectBefore.right,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('right-sidebar-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(tester.getRect(canvasFinder), equals(canvasRectBefore));
    expect(find.byKey(const Key('node-palette-search-field')), findsOneWidget);
    expect(
      tester.getTopLeft(sidebarFinder).dx < canvasRectBefore.right,
      isTrue,
    );

    final initialWidth = tester.getSize(sidebarFinder).width;
    await tester.drag(
      find.byKey(const Key('right-sidebar-resize-handle-hit')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();

    final widenedWidth = tester.getSize(sidebarFinder).width;
    expect(widenedWidth, greaterThan(initialWidth));
  });

  testWidgets('right overlay sidebar tab bar switches panels', (
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

    final sidebarFinder = find.byKey(const Key('right-overlay-sidebar'));
    expect(sidebarFinder, findsOneWidget);

    expect(find.byKey(const Key('sidebar_tab_nodes')), findsOneWidget);
    expect(find.byKey(const Key('sidebar_tab_inspector')), findsNothing);
    expect(find.byKey(const Key('sidebar_tab_runs')), findsNothing);
    expect(find.byKey(const Key('sidebar-tab-runs-button')), findsNothing);
    expect(find.text('Flows'), findsNothing);
    expect(find.text('Runs'), findsNothing);

    await tester.tap(find.byKey(const Key('sidebar-tab-inspector-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar_tab_inspector')), findsOneWidget);
    expect(find.text('Select a processor to inspect'), findsOneWidget);

    expect(find.byKey(const Key('sidebar_tab_nodes')), findsNothing);
  });

  testWidgets('message drawer log row renders and copy action works', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
      'client.message_drawer_open': false,
    });

    MessageCenter.instance.log(
      level: AppMessageLevel.info,
      source: AppMessageSource.app,
      message: 'Drawer test message',
    );

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

    expect(find.byKey(const Key('message-drawer-handle')), findsNothing);
    expect(
      find.byKey(const Key('message-drawer-toggle-button')),
      findsOneWidget,
    );
    expect(find.textContaining('Messages (1)'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    await tester.tap(find.byKey(const Key('message-drawer-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-drawer-panel')), findsOneWidget);
    expect(find.text('Drawer test message'), findsOneWidget);
    expect(find.text('INFO'), findsOneWidget);
    expect(
      find.byKey(const Key('message-drawer-search-field')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('message-drawer-panel')),
        matching: find.byIcon(Icons.copy_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    final labelText = tester.widget<Text>(find.text('Messages (0)'));
    final color = labelText.style?.color;
    expect(color, isNotNull);
    expect(
      color,
      isNot(
        equals(
          Theme.of(tester.element(find.text('Messages (0)'))).colorScheme.error,
        ),
      ),
    );

    final panelFinder = find.byKey(const Key('message-drawer-panel'));
    final sidebarFinder = find.byKey(const Key('right-overlay-sidebar'));
    final openSidebarPanelWidth = tester.getSize(panelFinder).width;
    final sidebarWidth = tester.getSize(sidebarFinder).width;
    expect(openSidebarPanelWidth, closeTo(1600 - sidebarWidth, 2));

    await tester.tap(find.byKey(const Key('right-sidebar-toggle')));
    await tester.pumpAndSettle();

    final closedSidebarPanelWidth = tester.getSize(panelFinder).width;
    expect(closedSidebarPanelWidth, greaterThan(openSidebarPanelWidth));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('message-drawer-panel')),
        matching: find.byIcon(Icons.copy_outlined),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    MessageCenter.instance.log(
      level: AppMessageLevel.warn,
      source: AppMessageSource.server,
      message: 'Another warning',
    );
    await tester.pumpAndSettle();
    expect(find.text('Another warning'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('message-drawer-search-field')),
      'another',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Another warning'), findsOneWidget);
    expect(find.text('Drawer test message'), findsNothing);

    await tester.tap(find.byKey(const Key('message-drawer-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Another warning'), findsOneWidget);
    expect(find.text('Drawer test message'), findsOneWidget);
  });
}
