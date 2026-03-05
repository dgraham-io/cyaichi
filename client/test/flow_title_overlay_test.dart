import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
  });

  testWidgets('flow title overlay renders and editing marks flow dirty', (
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
    expect(
      find.byKey(const Key('flow-title-edit-menu-button')),
      findsOneWidget,
    );
    expect(find.text('My Flow'), findsOneWidget);
    expect(find.textContaining('•'), findsNothing);

    await tester.tap(find.byKey(const Key('flow-title-display')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flow-title-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('flow-title-editor')),
      'Renamed Flow',
    );
    await tester.tap(find.byKey(const Key('flow-title-save')));
    await tester.pumpAndSettle();

    expect(find.text('Renamed Flow'), findsOneWidget);
    expect(find.textContaining('•'), findsOneWidget);
  });

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

    await tester.tap(find.byKey(const Key('flow-title-edit-menu-button')));
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

  testWidgets('floating toolbar renders with validate/run and tooltips', (
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

    expect(find.byKey(const Key('canvas-floating-toolbar')), findsOneWidget);
    expect(find.byKey(const Key('canvas-validate-button')), findsOneWidget);
    expect(find.byKey(const Key('canvas-run-button')), findsOneWidget);

    final validateTooltip = tester.widget<Tooltip>(
      find.byKey(const Key('canvas-validate-tooltip')),
    );
    expect(validateTooltip.message, 'Validate');

    final runTooltip = tester.widget<Tooltip>(
      find.byKey(const Key('canvas-run-tooltip')),
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
      find.byKey(const Key('canvas-run-button')),
    );
    expect(runButton.onPressed, isNull);

    final runTooltip = tester.widget<Tooltip>(
      find.byKey(const Key('canvas-run-tooltip')),
    );
    expect(runTooltip.message, 'Run (select a workspace)');
  });
}
