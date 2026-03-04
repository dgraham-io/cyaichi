import 'package:client/src/flow/primary_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setting primary on one write clears others', () {
    final writes = <WriteNodeOption>[
      const WriteNodeOption(
        nodeId: 'w1',
        title: 'Write 1',
        outputFile: 'a.txt',
        isPrimary: true,
      ),
      const WriteNodeOption(
        nodeId: 'w2',
        title: 'Write 2',
        outputFile: 'b.txt',
        isPrimary: false,
      ),
    ];

    final updated = setPrimaryWriteNode(writes, 'w2');

    expect(updated.first.isPrimary, isFalse);
    expect(updated.last.isPrimary, isTrue);
  });

  test('run output selection prefers primary write node', () {
    final writes = <WriteNodeOption>[
      const WriteNodeOption(
        nodeId: 'w1',
        title: 'Write 1',
        outputFile: 'a.txt',
        isPrimary: false,
      ),
      const WriteNodeOption(
        nodeId: 'w2',
        title: 'Write 2',
        outputFile: 'b.txt',
        isPrimary: true,
      ),
    ];

    final output = chooseRunOutputFile(writes: writes, primaryNodeId: 'w2');

    expect(output, 'b.txt');
  });
}
