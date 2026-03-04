import 'package:client/src/flow/node_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file.read template has expected ports and config', () {
    final template = NodeTypeRegistry.createTemplate('file.read');

    expect(template.typeId, 'file.read');
    expect(template.outputs, hasLength(1));
    expect(template.outputs.first.port, 'out');
    expect(template.outputs.first.schema, 'artifact/text');
    expect(template.config.containsKey('input_file'), isTrue);
    expect(template.config['input_file'], 'input.txt');
  });
}
