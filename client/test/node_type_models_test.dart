import 'package:client/src/models/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses node type list response from JSON', () {
    final parsed = parseNodeTypeListResponse(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'file.read',
          'display_name': 'File Read',
          'category': 'io',
          'inputs': <Map<String, dynamic>>[],
          'outputs': <Map<String, dynamic>>[
            <String, dynamic>{'port': 'out', 'schema': 'artifact/text'},
          ],
          'config_schema': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'input_file',
              'kind': 'string',
              'required': true,
              'label': 'Input file',
            },
          ],
        },
      ],
    });

    expect(parsed, hasLength(1));
    expect(parsed.first.type, 'file.read');
    expect(parsed.first.displayName, 'File Read');
    expect(parsed.first.outputs.single.port, 'out');
    expect(parsed.first.outputs.single.schema, 'artifact/text');
    expect(parsed.first.configSchema.single.key, 'input_file');
    expect(parsed.first.configSchema.single.kind, 'string');
    expect(parsed.first.configSchema.single.required, isTrue);
  });
}
