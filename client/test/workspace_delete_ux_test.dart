import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WorkspaceDeleteApiClient extends ApiClient {
  _WorkspaceDeleteApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  final List<WorkspaceListItem> _items = <WorkspaceListItem>[
    WorkspaceListItem(
      workspaceId: '11111111-1111-1111-1111-111111111111',
      name: 'Workspace One',
      createdAt: '2026-03-05T00:00:00Z',
    ),
  ];

  var _counter = 1;

  @override
  void close() {}

  @override
  Future<List<WorkspaceListItem>> getWorkspaces() async {
    return List<WorkspaceListItem>.from(_items);
  }

  @override
  Future<WorkspaceDeleted> deleteWorkspace({
    required String workspaceId,
  }) async {
    _items.removeWhere((item) => item.workspaceId == workspaceId);
    return WorkspaceDeleted(
      workspaceId: workspaceId,
      verId: 'deleted-ver',
      deleted: true,
    );
  }

  @override
  Future<WorkspaceCreated> createWorkspace({required String name}) async {
    _counter += 1;
    final id = '22222222-2222-2222-2222-22222222222$_counter';
    _items.add(
      WorkspaceListItem(
        workspaceId: id,
        name: name,
        createdAt: '2026-03-05T00:00:00Z',
      ),
    );
    return WorkspaceCreated(workspaceId: id, docId: id, verId: 'v-$_counter');
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
  testWidgets('delete workspace clears selection and opens select dialog', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.selected_workspace_id': '11111111-1111-1111-1111-111111111111',
    });
    final fake = _WorkspaceDeleteApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: FlowCanvasScreen(
          apiClientFactory:
              ({
                required String baseUrl,
                required int runRequestTimeoutSeconds,
              }) => fake,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.workspaces));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Select workspace'), findsAtLeastNWidgets(1));
    expect(find.text('No workspace selected'), findsOneWidget);
  });

  testWidgets(
    'select workspace dialog has New workspace button and opens dialog',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final fake = _WorkspaceDeleteApiClient();

      await tester.pumpWidget(
        MaterialApp(
          home: FlowCanvasScreen(
            apiClientFactory:
                ({
                  required String baseUrl,
                  required int runRequestTimeoutSeconds,
                }) => fake,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.workspaces));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Select workspace'), findsAtLeastNWidgets(1));
      expect(find.text('New workspace'), findsOneWidget);
      await tester.tap(find.text('New workspace'));
      await tester.pumpAndSettle();

      expect(find.text('New workspace'), findsOneWidget);
    },
  );
}
