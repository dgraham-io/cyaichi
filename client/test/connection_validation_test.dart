import 'package:client/src/flow/connection_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows artifact/text output to artifact/text input', () {
    final result = validateTypedConnection(
      sourceIsOutput: true,
      targetIsInput: true,
      sourceSchema: 'artifact/text',
      targetSchema: 'artifact/text',
    );

    expect(result.allowed, isTrue);
    expect(result.reason, isNull);
  });

  test('rejects mismatched schema artifact/output_file to artifact/text', () {
    final result = validateTypedConnection(
      sourceIsOutput: true,
      targetIsInput: true,
      sourceSchema: 'artifact/output_file',
      targetSchema: 'artifact/text',
    );

    expect(result.allowed, isFalse);
    expect(result.reason, contains('schema mismatch'));
  });
}
