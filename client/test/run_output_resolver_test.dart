import 'package:client/src/flow/run_output_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves run outputs and fetches artifacts for preview', () async {
    final fetched = <String>[];
    final runBody = <String, dynamic>{
      'outputs': [
        {
          'artifact_ref': {
            'doc_id': 'out-doc',
            'ver_id': 'out-ver',
            'selector': 'pinned',
          },
        },
      ],
      'invocations': [
        {
          'node_id': 'n_write',
          'inputs': [
            {
              'artifact_ref': {
                'doc_id': 'text-doc',
                'ver_id': 'text-ver',
                'selector': 'pinned',
              },
            },
          ],
          'outputs': [
            {
              'artifact_ref': {
                'doc_id': 'out-doc',
                'ver_id': 'out-ver',
                'selector': 'pinned',
              },
            },
          ],
        },
      ],
    };

    final resolution = await resolveRunOutputs(
      runBody: runBody,
      fetchArtifactDocument:
          ({required String docId, required String verId}) async {
            fetched.add('$docId@$verId');
            if (docId == 'out-doc') {
              return <String, dynamic>{
                'body': <String, dynamic>{
                  'schema': 'artifact/output_file',
                  'payload': <String, dynamic>{
                    'path': 'output.txt',
                    'bytes': 42,
                  },
                },
              };
            }
            return <String, dynamic>{
              'body': <String, dynamic>{
                'schema': 'artifact/text',
                'payload': <String, dynamic>{'text': 'preview from upstream'},
              },
            };
          },
    );

    expect(resolution.outputArtifacts, hasLength(1));
    expect(resolution.outputArtifacts.first.path, 'output.txt');
    expect(resolution.outputArtifacts.first.bytes, 42);
    expect(resolution.previewText, 'preview from upstream');
    expect(fetched, contains('out-doc@out-ver'));
    expect(fetched, contains('text-doc@text-ver'));
  });
}
