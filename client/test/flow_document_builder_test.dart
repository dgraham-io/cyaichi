import 'package:client/src/flow/flow_document_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildFlowDocumentEnvelope includes required keys', () {
    final document = buildFlowDocumentEnvelope(
      workspaceId: '4a44027a-7c8f-4ff1-bfda-a7360f219f0a',
      docId: '06a92f74-e006-4a3b-85c9-b71f0b87df06',
      verId: '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4',
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      title: 'Smoke Flow',
      nodes: const <FlowNodeSnapshot>[
        FlowNodeSnapshot(
          id: 'n_read',
          type: 'file.read',
          title: 'Read',
          inputs: <FlowPort>[],
          outputs: <FlowPort>[FlowPort(port: 'out', schema: 'artifact/text')],
          config: <String, dynamic>{},
        ),
      ],
      edges: const <FlowEdgeSnapshot>[],
    );

    expect(document['doc_type'], 'flow');
    expect(document['doc_id'], '06a92f74-e006-4a3b-85c9-b71f0b87df06');
    expect(document['ver_id'], '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4');
    expect(document['workspace_id'], '4a44027a-7c8f-4ff1-bfda-a7360f219f0a');
    expect(document['created_at'], '2026-01-02T03:04:05.000Z');

    final meta = document['meta'] as Map<String, dynamic>;
    expect(meta['title'], 'Smoke Flow');

    final body = document['body'] as Map<String, dynamic>;
    expect(body['mode_hint'], 'hybrid');
    expect(body['nodes'], isA<List<dynamic>>());
    expect(body['edges'], isA<List<dynamic>>());

    final nodes = body['nodes'] as List<dynamic>;
    expect(nodes, hasLength(1));
    final first = nodes.first as Map<String, dynamic>;
    expect(first['id'], 'n_read');
    expect(first['type'], 'file.read');
  });
}
