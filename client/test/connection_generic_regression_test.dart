import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

void main() {
  test(
    'controller with dynamic connection generic can create a connection',
    () {
      final controller = NodeFlowController<Map<String, dynamic>, dynamic>(
        config: NodeFlowConfig(scrollToZoom: false),
      );
      addTearDown(controller.dispose);

      controller.addNode(
        Node<Map<String, dynamic>>(
          id: 'A',
          type: 'file.read',
          position: Offset.zero,
          size: const Size(220, 132),
          ports: <Port>[
            Port(
              id: 'out',
              name: 'out',
              position: PortPosition.right,
              type: PortType.output,
              offset: Offset(0, 60),
              multiConnections: true,
            ),
          ],
          data: <String, dynamic>{},
        ),
      );

      controller.addNode(
        Node<Map<String, dynamic>>(
          id: 'B',
          type: 'llm.chat',
          position: const Offset(300, 0),
          size: const Size(220, 132),
          ports: <Port>[
            Port(
              id: 'in',
              name: 'in',
              position: PortPosition.left,
              type: PortType.input,
              offset: Offset(0, 60),
              multiConnections: true,
            ),
          ],
          data: <String, dynamic>{},
        ),
      );

      controller.createConnection('A', 'out', 'B', 'in');

      expect(controller.connections.length, 1);
      expect(controller.connections.first.sourceNodeId, 'A');
      expect(controller.connections.first.targetNodeId, 'B');
    },
  );
}
