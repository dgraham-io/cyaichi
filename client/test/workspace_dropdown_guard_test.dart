import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyWorkspaceApiClient extends ApiClient {
  _EmptyWorkspaceApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  @override
  void close() {}

  @override
  Future<List<WorkspaceListItem>> getWorkspaces() async {
    return <WorkspaceListItem>[];
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
  testWidgets(
    'workspace dropdown stays safe when selected id exists in prefs but items are empty',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'client.selected_workspace_id': 'stale-workspace-id',
      });

      final fake = _EmptyWorkspaceApiClient();
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
      expect(tester.takeException(), isNull);
      expect(find.text('Select workspace'), findsOneWidget);
    },
  );
}
