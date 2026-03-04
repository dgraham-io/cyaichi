import 'package:client/src/flow/node_registry.dart';

class FlowValidationIssue {
  const FlowValidationIssue(this.message);

  final String message;
}

class FlowValidationResult {
  const FlowValidationResult({required this.errors, required this.warnings});

  final List<FlowValidationIssue> errors;
  final List<FlowValidationIssue> warnings;

  bool get hasErrors => errors.isNotEmpty;
}

class FlowValidationNode {
  const FlowValidationNode({
    required this.id,
    required this.type,
    required this.inputPorts,
    required this.outputPorts,
    required this.config,
  });

  final String id;
  final String type;
  final List<String> inputPorts;
  final List<String> outputPorts;
  final Map<String, dynamic> config;
}

class FlowValidationEdge {
  const FlowValidationEdge({
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
  });

  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;
}

FlowValidationResult validateFlowGraph({
  required List<FlowValidationNode> nodes,
  required List<FlowValidationEdge> edges,
}) {
  final errors = <FlowValidationIssue>[];
  final warnings = <FlowValidationIssue>[];
  final nodeById = <String, FlowValidationNode>{};

  for (final node in nodes) {
    nodeById[node.id] = node;
  }

  for (final edge in edges) {
    final source = nodeById[edge.sourceNodeId];
    final target = nodeById[edge.targetNodeId];
    if (source == null) {
      errors.add(
        FlowValidationIssue('Edge source node not found: ${edge.sourceNodeId}'),
      );
      continue;
    }
    if (target == null) {
      errors.add(
        FlowValidationIssue('Edge target node not found: ${edge.targetNodeId}'),
      );
      continue;
    }
    if (!source.outputPorts.contains(edge.sourcePortId)) {
      errors.add(
        FlowValidationIssue(
          'Source port ${edge.sourcePortId} does not exist on node ${source.id}',
        ),
      );
    }
    if (!target.inputPorts.contains(edge.targetPortId)) {
      errors.add(
        FlowValidationIssue(
          'Target port ${edge.targetPortId} does not exist on node ${target.id}',
        ),
      );
    }
  }

  for (final node in nodes) {
    final def = NodeTypeRegistry.byType(node.type);
    if (def == null) {
      continue;
    }
    for (final field in def.inspectorFields.where((field) => field.required)) {
      final value = (node.config[field.key] as String?)?.trim() ?? '';
      if (value.isEmpty) {
        errors.add(
          FlowValidationIssue(
            '${def.displayName} (${node.id}) is missing ${field.key}',
          ),
        );
      }
    }
  }

  final readNodes = nodes.where((node) => node.type == 'file.read').toList();
  final writeNodes = nodes.where((node) => node.type == 'file.write').toList();

  if (readNodes.length != 1) {
    warnings.add(
      const FlowValidationIssue(
        'MVP warning: expected exactly one file.read node.',
      ),
    );
  }
  if (writeNodes.length != 1) {
    warnings.add(
      const FlowValidationIssue(
        'MVP warning: expected exactly one file.write node.',
      ),
    );
  }

  if (readNodes.length == 1 && writeNodes.length == 1) {
    final adjacency = <String, Set<String>>{};
    final reverse = <String, Set<String>>{};
    for (final node in nodes) {
      adjacency[node.id] = <String>{};
      reverse[node.id] = <String>{};
    }
    for (final edge in edges) {
      adjacency
          .putIfAbsent(edge.sourceNodeId, () => <String>{})
          .add(edge.targetNodeId);
      reverse
          .putIfAbsent(edge.targetNodeId, () => <String>{})
          .add(edge.sourceNodeId);
    }

    final start = readNodes.first.id;
    final end = writeNodes.first.id;
    final reachableFromStart = _traverse(adjacency, start);
    final canReachEnd = _traverse(reverse, end);

    if (!reachableFromStart.contains(end)) {
      warnings.add(
        const FlowValidationIssue(
          'MVP warning: file.read is not connected to file.write.',
        ),
      );
    }

    for (final node in nodes) {
      if (!reachableFromStart.contains(node.id) ||
          !canReachEnd.contains(node.id)) {
        warnings.add(
          FlowValidationIssue(
            'MVP warning: node ${node.id} is outside single end-to-end chain.',
          ),
        );
      }
    }
  }

  return FlowValidationResult(errors: errors, warnings: warnings);
}

Set<String> _traverse(Map<String, Set<String>> graph, String start) {
  final visited = <String>{};
  final stack = <String>[start];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (!visited.add(node)) {
      continue;
    }
    for (final next in graph[node] ?? const <String>{}) {
      stack.add(next);
    }
  }
  return visited;
}
