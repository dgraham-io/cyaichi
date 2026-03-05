import 'package:client/src/flow/flow_document_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses server flow envelope with 3 nodes and 2 edges', () {
    final doc = <String, dynamic>{
      'doc_type': 'flow',
      'doc_id': '11111111-1111-1111-1111-111111111111',
      'ver_id': '22222222-2222-2222-2222-222222222222',
      'workspace_id': '33333333-3333-3333-3333-333333333333',
      'created_at': '2026-03-04T00:00:00Z',
      'body': <String, dynamic>{
        'nodes': [
          {
            'id': 'n_read',
            'type': 'file.read',
            'inputs': [],
            'outputs': [
              {'port': 'out', 'schema': 'artifact/text'},
            ],
            'config': <String, dynamic>{},
          },
          {
            'id': 'n_chat',
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
            'id': 'n_write',
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
            'from': {'node': 'n_read', 'port': 'out'},
            'to': {'node': 'n_chat', 'port': 'in'},
          },
          {
            'from': {'node': 'n_chat', 'port': 'out'},
            'to': {'node': 'n_write', 'port': 'in'},
          },
        ],
      },
    };

    final parsed = parseFlowDocumentEnvelope(doc);
    expect(parsed.nodes, hasLength(3));
    expect(parsed.edges, hasLength(2));
  });
}
