import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PrimaryOutputApiClient extends ApiClient {
  _PrimaryOutputApiClient()
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
          NodeTypeConfigFieldDef(
            key: 'primary',
            kind: 'bool',
            required: false,
            label: 'Primary output',
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

  testWidgets('file.write primary badge appears after selection', (
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
              }) => _PrimaryOutputApiClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addWrite = find.byKey(const Key('add-file.write'));
    await tester.tap(addWrite);
    await tester.pumpAndSettle();
    await tester.tap(addWrite);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sidebar-tab-inspector-button')));
    await tester.pumpAndSettle();

    expect(find.text('Set as Primary Output'), findsOneWidget);
    await tester.tap(find.text('Set as Primary Output'));
    await tester.pumpAndSettle();

    expect(find.text('Primary'), findsWidgets);
  });
}
