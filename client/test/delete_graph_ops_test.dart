import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

void main() {
  test('can delete connection then delete node without dangling edges', () {
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
            offset: const Offset(0, 60),
            multiConnections: true,
          ),
        ],
        data: <String, dynamic>{},
      ),
    );
    controller.addNode(
      Node<Map<String, dynamic>>(
        id: 'B',
        type: 'file.write',
        position: const Offset(300, 0),
        size: const Size(220, 132),
        ports: <Port>[
          Port(
            id: 'in',
            name: 'in',
            position: PortPosition.left,
            type: PortType.input,
            offset: const Offset(0, 60),
            multiConnections: true,
          ),
        ],
        data: <String, dynamic>{},
      ),
    );

    controller.createConnection('A', 'out', 'B', 'in');
    expect(controller.connections.length, 1);

    final connectionId = controller.connections.first.id;
    controller.removeConnection(connectionId);
    expect(controller.connections.length, 0);

    controller.removeNode('A');
    expect(controller.nodes.containsKey('A'), isFalse);
    expect(controller.nodes.length, 1);
    expect(controller.connections, isEmpty);
  });
}
