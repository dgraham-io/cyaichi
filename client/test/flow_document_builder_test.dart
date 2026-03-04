import 'package:client/src/flow/flow_document_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleNodes = <FlowNodeSnapshot>[
    FlowNodeSnapshot(
      id: 'n_read',
      type: 'file.read',
      title: 'Read',
      inputs: <FlowPort>[],
      outputs: <FlowPort>[FlowPort(port: 'out', schema: 'artifact/text')],
      config: <String, dynamic>{},
    ),
  ];
  const sampleEdges = <FlowEdgeSnapshot>[];

  test('buildFlowDocumentEnvelope includes required keys', () {
    final document = buildFlowDocumentEnvelope(
      workspaceId: '4a44027a-7c8f-4ff1-bfda-a7360f219f0a',
      docId: '06a92f74-e006-4a3b-85c9-b71f0b87df06',
      verId: '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4',
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      title: 'Smoke Flow',
      parents: const <String>['11111111-1111-1111-1111-111111111111'],
      nodes: sampleNodes,
      edges: sampleEdges,
    );

    expect(document['doc_type'], 'flow');
    expect(document['doc_id'], '06a92f74-e006-4a3b-85c9-b71f0b87df06');
    expect(document['ver_id'], '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4');
    expect(document['workspace_id'], '4a44027a-7c8f-4ff1-bfda-a7360f219f0a');
    expect(document['created_at'], '2026-01-02T03:04:05.000Z');
    expect(document['parents'], const <String>[
      '11111111-1111-1111-1111-111111111111',
    ]);

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

  test(
    'buildNewVersionFlowDocument keeps doc_id and sets parent to prior ver',
    () {
      final current = ParsedFlowDocument(
        workspaceId: '4a44027a-7c8f-4ff1-bfda-a7360f219f0a',
        docId: '06a92f74-e006-4a3b-85c9-b71f0b87df06',
        verId: '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4',
        createdAt: '2026-01-01T01:00:00Z',
        parents: const <String>[],
        title: 'v1',
        nodes: sampleNodes,
        edges: sampleEdges,
      );
      final next = buildNewVersionFlowDocument(
        current: current,
        newVerId: '22222222-2222-2222-2222-222222222222',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        title: 'v2',
        nodes: sampleNodes,
        edges: sampleEdges,
      );

      expect(next['doc_id'], current.docId);
      expect(next['ver_id'], '22222222-2222-2222-2222-222222222222');
      expect(next['parents'], <String>[current.verId]);
    },
  );

  test(
    'buildDuplicateFlowDocument creates new identity with empty parents',
    () {
      final duplicated = buildDuplicateFlowDocument(
        workspaceId: '4a44027a-7c8f-4ff1-bfda-a7360f219f0a',
        docId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        verId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        title: 'Dup',
        nodes: sampleNodes,
        edges: sampleEdges,
      );

      expect(duplicated['doc_id'], 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(duplicated['ver_id'], 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      expect(duplicated['parents'], const <String>[]);
    },
  );

  test('parseFlowDocumentEnvelope parses minimal server flow JSON', () {
    final parsed = parseFlowDocumentEnvelope(<String, dynamic>{
      'doc_type': 'flow',
      'doc_id': '06a92f74-e006-4a3b-85c9-b71f0b87df06',
      'ver_id': '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4',
      'workspace_id': '4a44027a-7c8f-4ff1-bfda-a7360f219f0a',
      'created_at': '2026-01-02T03:04:05Z',
      'parents': <String>['11111111-1111-1111-1111-111111111111'],
      'meta': <String, dynamic>{'title': 'Server Flow'},
      'body': <String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'n_read',
            'type': 'file.read',
            'title': 'Read',
            'inputs': <Map<String, dynamic>>[],
            'outputs': <Map<String, dynamic>>[
              <String, dynamic>{'port': 'out', 'schema': 'artifact/text'},
            ],
            'config': <String, dynamic>{},
          },
        ],
        'edges': <Map<String, dynamic>>[],
      },
    });

    expect(parsed.docId, '06a92f74-e006-4a3b-85c9-b71f0b87df06');
    expect(parsed.verId, '897f2bd1-1158-4f31-a5f6-90f2f10ef7f4');
    expect(parsed.parents, <String>['11111111-1111-1111-1111-111111111111']);
    expect(parsed.nodes.length, 1);
    expect(parsed.nodes.first.id, 'n_read');
  });
}
