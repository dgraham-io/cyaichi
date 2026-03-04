import 'package:client/src/flow/primary_output.dart';
import 'package:client/src/flow/run_request_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run request builder uses node.config defaults', () {
    final writes = <WriteNodeOption>[
      const WriteNodeOption(
        nodeId: 'w1',
        title: 'Write',
        outputFile: 'config-output.txt',
        isPrimary: true,
      ),
    ];

    final result = buildRunRequestParams(
      enteredInputFile: '',
      enteredOutputFile: '',
      readNodeConfigInputFiles: const <String>['config-input.txt'],
      writeNodes: writes,
      preferredPrimaryWriteNodeId: null,
    );

    expect(result.isValid, isTrue);
    expect(result.params, isNotNull);
    expect(result.params!.inputFile, 'config-input.txt');
    expect(result.params!.outputFile, 'config-output.txt');
    expect(result.params!.primaryWriteNodeId, 'w1');
  });
}
