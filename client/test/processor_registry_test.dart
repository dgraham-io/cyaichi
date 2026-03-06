import 'package:client/src/flow/processor_registry.dart';
import 'package:client/src/models/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file.read template has expected ports and config', () {
    final registry = ProcessorTypeRegistry.fallback();
    final template = registry.createTemplate('file.read');

    expect(template.typeId, 'file.read');
    expect(template.outputs, hasLength(1));
    expect(template.outputs.first.port, 'out');
    expect(template.outputs.first.schema, 'artifact/text');
    expect(template.config.containsKey('input_file'), isTrue);
    expect(template.config['input_file'], '');
  });

  test(
    'processor created from server node type has ports and default config',
    () {
      final defs = <NodeTypeDef>[
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
      final registry = ProcessorTypeRegistry.fromServerProcessorTypes(
        defs,
        source: ProcessorTypeRegistrySource.server,
      );

      final template = registry.createTemplate('file.write');

      expect(template.inputs.single.port, 'in');
      expect(template.inputs.single.schema, 'artifact/text');
      expect(template.outputs.single.port, 'out');
      expect(template.outputs.single.schema, 'artifact/output_file');
      expect(template.config['output_file'], '');
      expect(template.config['primary'], false);
    },
  );
}
