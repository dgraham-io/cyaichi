import 'package:client/api/api_client.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFlowApiClient extends ApiClient {
  _MockFlowApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        runRequestTimeout: const Duration(seconds: 300),
      );

  @override
  void close() {}

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
      NodeTypeDef(
        type: 'llm.chat',
        displayName: 'LLM Chat',
        category: 'ai',
        inputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'in', schema: 'artifact/text'),
        ],
        outputs: <NodeTypePortDef>[
          NodeTypePortDef(port: 'out', schema: 'artifact/text'),
        ],
        configSchema: const <NodeTypeConfigFieldDef>[],
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
        configSchema: const <NodeTypeConfigFieldDef>[],
      ),
    ];
  }

  @override
  Future<List<FlowListItem>> getFlows({required String workspaceId}) async {
    return <FlowListItem>[
      FlowListItem(
        docId: 'flow-doc',
        verId: 'flow-ver',
        createdAt: '2026-03-04T00:00:00Z',
        ref: '',
        title: 'Autoload Flow',
      ),
    ];
  }

  @override
  Future<List<RunListItem>> getRuns({required String workspaceId}) async {
    return const <RunListItem>[];
  }

  @override
  Future<List<NoteListItem>> getNotes({required String workspaceId}) async {
    return const <NoteListItem>[];
  }

  @override
  Future<Map<String, dynamic>> getDocument({
    required String docType,
    required String docId,
    required String verId,
  }) async {
    if (docType == 'flow' && docId == 'flow-doc' && verId == 'flow-ver') {
      return <String, dynamic>{
        'doc_type': 'flow',
        'doc_id': docId,
        'ver_id': verId,
        'workspace_id': 'ws-1',
        'created_at': '2026-03-04T00:00:00Z',
        'body': <String, dynamic>{
          'nodes': [
            {
              'id': 'n1',
              'type': 'file.read',
              'inputs': [],
              'outputs': [
                {'port': 'out', 'schema': 'artifact/text'},
              ],
              'config': <String, dynamic>{},
            },
            {
              'id': 'n2',
              'type': 'llm.chat',
              'inputs': [
                {'port': 'in', 'schema': 'artifact/text'},
              ],
              'outputs': [
                {'port': 'out', 'schema': 'artifact/text'},
              ],
              'config': <String, dynamic>{},
            },
            {
              'id': 'n3',
              'type': 'file.write',
              'inputs': [
                {'port': 'in', 'schema': 'artifact/text'},
              ],
              'outputs': [
                {'port': 'out', 'schema': 'artifact/output_file'},
              ],
              'config': <String, dynamic>{},
            },
          ],
          'edges': [
            {
              'from': {'node': 'n1', 'port': 'out'},
              'to': {'node': 'n2', 'port': 'in'},
            },
            {
              'from': {'node': 'n2', 'port': 'out'},
              'to': {'node': 'n3', 'port': 'in'},
            },
          ],
        },
      };
    }
    return <String, dynamic>{};
  }
}

void main() {
  testWidgets('autoloads latest flow on startup and renders 3 nodes/2 edges', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'client.workspace_ids': <String>['ws-1'],
      'client.selected_workspace_id': 'ws-1',
    });

    final fake = _MockFlowApiClient();
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

    final dynamic state = tester.state(find.byType(FlowCanvasScreen));
    expect(state.debugCanvasNodeCount, 3);
    expect(state.debugCanvasEdgeCount, 2);
  });
}
