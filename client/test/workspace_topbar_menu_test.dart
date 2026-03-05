import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WorkspaceMenuApiClient extends ApiClient {
  _WorkspaceMenuApiClient({required this.workspaces})
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  final List<WorkspaceListItem> workspaces;

  @override
  void close() {}

  @override
  Future<List<WorkspaceListItem>> getWorkspaces() async {
    return workspaces;
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
  testWidgets('top bar renders No workspace and workspace menu options', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fake = _WorkspaceMenuApiClient(
      workspaces: const <WorkspaceListItem>[],
    );
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

    expect(find.text('No workspace'), findsOneWidget);

    final editButton = find.widgetWithIcon(IconButton, Icons.edit_outlined);
    expect(editButton, findsOneWidget);
    expect(find.byIcon(Icons.workspaces), findsNothing);

    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.text('Rename workspace'), findsOneWidget);
    expect(find.text('Select workspace'), findsAtLeastNWidgets(1));
    expect(find.text('New workspace'), findsOneWidget);
    expect(find.text('Delete workspace'), findsOneWidget);
  });

  testWidgets('select workspace dialog updates top bar workspace label', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fake = _WorkspaceMenuApiClient(
      workspaces: <WorkspaceListItem>[
        WorkspaceListItem(
          workspaceId: '11111111-1111-1111-1111-111111111111',
          name: 'Demo Workspace',
          createdAt: '2026-03-05T00:00:00Z',
        ),
      ],
    );
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

    expect(find.text('No workspace'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo Workspace'));
    await tester.pumpAndSettle();

    expect(find.text('Demo Workspace'), findsOneWidget);
  });
}
