class FlowPort {
  const FlowPort({required this.port, required this.schema});

  final String port;
  final String schema;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'port': port, 'schema': schema};
  }
}

class FlowNodeSnapshot {
  const FlowNodeSnapshot({
    required this.id,
    required this.type,
    required this.title,
    required this.inputs,
    required this.outputs,
    required this.config,
  });

  final String id;
  final String type;
  final String title;
  final List<FlowPort> inputs;
  final List<FlowPort> outputs;
  final Map<String, dynamic> config;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'inputs': inputs.map((port) => port.toJson()).toList(),
      'outputs': outputs.map((port) => port.toJson()).toList(),
      'config': config,
    };
  }
}

class FlowEdgeSnapshot {
  const FlowEdgeSnapshot({
    required this.sourceNode,
    required this.sourcePort,
    required this.targetNode,
    required this.targetPort,
  });

  final String sourceNode;
  final String sourcePort;
  final String targetNode;
  final String targetPort;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'from': <String, dynamic>{'node': sourceNode, 'port': sourcePort},
      'to': <String, dynamic>{'node': targetNode, 'port': targetPort},
    };
  }
}

Map<String, dynamic> buildFlowDocumentEnvelope({
  required String workspaceId,
  required String docId,
  required String verId,
  required DateTime createdAt,
  required String title,
  required List<FlowNodeSnapshot> nodes,
  required List<FlowEdgeSnapshot> edges,
}) {
  final trimmedTitle = title.trim();
  final body = <String, dynamic>{
    'mode_hint': 'hybrid',
    'nodes': nodes.map((node) => node.toJson()).toList(),
    'edges': edges.map((edge) => edge.toJson()).toList(),
  };

  final document = <String, dynamic>{
    'doc_type': 'flow',
    'doc_id': docId,
    'ver_id': verId,
    'workspace_id': workspaceId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'body': body,
  };

  if (trimmedTitle.isNotEmpty) {
    document['meta'] = <String, dynamic>{'title': trimmedTitle};
  }

  return document;
}
