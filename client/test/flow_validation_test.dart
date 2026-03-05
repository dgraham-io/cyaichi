import 'package:client/src/flow/flow_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validation flips when flow model is corrected', () {
    final invalid = validateFlowGraph(
      nodes: const <FlowValidationNode>[
        FlowValidationNode(
          id: 'r1',
          type: 'file.read',
          inputPorts: <String>[],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'input_file': 'input.txt'},
        ),
        FlowValidationNode(
          id: 'w1',
          type: 'file.write',
          inputPorts: <String>['in'],
          outputPorts: <String>['out'],
          config: <String, dynamic>{},
        ),
      ],
      edges: const <FlowValidationEdge>[
        FlowValidationEdge(
          sourceNodeId: 'r1',
          sourcePortId: 'out',
          targetNodeId: 'w1',
          targetPortId: 'in',
        ),
      ],
    );

    final valid = validateFlowGraph(
      nodes: const <FlowValidationNode>[
        FlowValidationNode(
          id: 'r1',
          type: 'file.read',
          inputPorts: <String>[],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'input_file': 'input.txt'},
        ),
        FlowValidationNode(
          id: 'w1',
          type: 'file.write',
          inputPorts: <String>['in'],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'output_file': 'output.txt'},
        ),
      ],
      edges: const <FlowValidationEdge>[
        FlowValidationEdge(
          sourceNodeId: 'r1',
          sourcePortId: 'out',
          targetNodeId: 'w1',
          targetPortId: 'in',
        ),
      ],
    );

    expect(invalid.hasErrors, isTrue);
    expect(valid.hasErrors, isFalse);
  });

  test('multiple file.write nodes produce warnings, not errors', () {
    final result = validateFlowGraph(
      nodes: const <FlowValidationNode>[
        FlowValidationNode(
          id: 'r1',
          type: 'file.read',
          inputPorts: <String>[],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'input_file': 'input.txt'},
        ),
        FlowValidationNode(
          id: 'w1',
          type: 'file.write',
          inputPorts: <String>['in'],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'output_file': 'out1.txt'},
        ),
        FlowValidationNode(
          id: 'w2',
          type: 'file.write',
          inputPorts: <String>['in'],
          outputPorts: <String>['out'],
          config: <String, dynamic>{'output_file': 'out2.txt'},
        ),
      ],
      edges: const <FlowValidationEdge>[
        FlowValidationEdge(
          sourceNodeId: 'r1',
          sourcePortId: 'out',
          targetNodeId: 'w1',
          targetPortId: 'in',
        ),
      ],
    );

    expect(result.errors, isEmpty);
    expect(result.warnings, isNotEmpty);
    expect(
      result.warnings.any((warning) => warning.message.contains('file.write')),
      isTrue,
    );
    expect(
      result.warnings.any(
        (warning) => warning.message.contains('primary output'),
      ),
      isTrue,
    );
  });
}
