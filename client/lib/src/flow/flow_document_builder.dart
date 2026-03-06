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

class ParsedFlowDocument {
  const ParsedFlowDocument({
    required this.workspaceId,
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.parents,
    required this.title,
    required this.nodes,
    required this.edges,
  });

  final String workspaceId;
  final String docId;
  final String verId;
  final String createdAt;
  final List<String> parents;
  final String title;
  final List<FlowNodeSnapshot> nodes;
  final List<FlowEdgeSnapshot> edges;
}

Map<String, dynamic> buildFlowDocumentEnvelope({
  required String workspaceId,
  required String docId,
  required String verId,
  required DateTime createdAt,
  required String title,
  required List<String> parents,
  required List<FlowNodeSnapshot> nodes,
  required List<FlowEdgeSnapshot> edges,
}) {
  final trimmedTitle = title.trim();
  // UI terminology uses "processor", but the persisted schema keeps body.nodes.
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
    'parents': parents,
    'body': body,
  };

  if (trimmedTitle.isNotEmpty) {
    document['meta'] = <String, dynamic>{'title': trimmedTitle};
  }

  return document;
}

Map<String, dynamic> buildNewVersionFlowDocument({
  required ParsedFlowDocument current,
  required String newVerId,
  required DateTime createdAt,
  required String title,
  required List<FlowNodeSnapshot> nodes,
  required List<FlowEdgeSnapshot> edges,
}) {
  return buildFlowDocumentEnvelope(
    workspaceId: current.workspaceId,
    docId: current.docId,
    verId: newVerId,
    createdAt: createdAt,
    title: title,
    parents: <String>[current.verId],
    nodes: nodes,
    edges: edges,
  );
}

Map<String, dynamic> buildDuplicateFlowDocument({
  required String workspaceId,
  required String docId,
  required String verId,
  required DateTime createdAt,
  required String title,
  required List<FlowNodeSnapshot> nodes,
  required List<FlowEdgeSnapshot> edges,
}) {
  return buildFlowDocumentEnvelope(
    workspaceId: workspaceId,
    docId: docId,
    verId: verId,
    createdAt: createdAt,
    title: title,
    parents: const <String>[],
    nodes: nodes,
    edges: edges,
  );
}

ParsedFlowDocument parseFlowDocumentEnvelope(Map<String, dynamic> document) {
  final docType = document['doc_type'];
  if (docType != 'flow') {
    throw const FormatException('Document is not a flow.');
  }

  final workspaceId = document['workspace_id'];
  final docId = document['doc_id'];
  final verId = document['ver_id'];
  final createdAt = document['created_at'];
  if (workspaceId is! String ||
      docId is! String ||
      verId is! String ||
      createdAt is! String) {
    throw const FormatException('Flow envelope is missing required fields.');
  }

  final parentsRaw = document['parents'];
  final parents = parentsRaw is List
      ? parentsRaw.whereType<String>().toList(growable: false)
      : const <String>[];

  final meta = document['meta'];
  var title = '';
  if (meta is Map<String, dynamic>) {
    final parsedTitle = meta['title'];
    if (parsedTitle is String) {
      title = parsedTitle;
    }
  }

  final body = document['body'];
  if (body is! Map<String, dynamic>) {
    throw const FormatException('Missing body object.');
  }

  final nodesRaw = body['nodes'];
  final edgesRaw = body['edges'];
  if (nodesRaw is! List) {
    throw const FormatException('body.nodes must be an array.');
  }
  if (edgesRaw is! List) {
    throw const FormatException('body.edges must be an array.');
  }

  final nodes = <FlowNodeSnapshot>[];
  for (final node in nodesRaw) {
    if (node is! Map<String, dynamic>) {
      continue;
    }

    final id = node['id'];
    final type = node['type'];
    if (id is! String || type is! String) {
      continue;
    }
    final nodeTitle = node['title'];
    final inputs = _parsePorts(node['inputs']);
    final outputs = _parsePorts(node['outputs']);
    final config = node['config'];
    nodes.add(
      FlowNodeSnapshot(
        id: id,
        type: type,
        title: nodeTitle is String ? nodeTitle : type,
        inputs: inputs,
        outputs: outputs,
        config: config is Map<String, dynamic>
            ? Map<String, dynamic>.from(config)
            : <String, dynamic>{},
      ),
    );
  }

  final edges = <FlowEdgeSnapshot>[];
  for (final edge in edgesRaw) {
    if (edge is! Map<String, dynamic>) {
      continue;
    }
    final from = edge['from'];
    final to = edge['to'];
    if (from is! Map<String, dynamic> || to is! Map<String, dynamic>) {
      continue;
    }
    final sourceNode = from['node'];
    final sourcePort = from['port'];
    final targetNode = to['node'];
    final targetPort = to['port'];
    if (sourceNode is! String ||
        sourcePort is! String ||
        targetNode is! String ||
        targetPort is! String) {
      continue;
    }
    edges.add(
      FlowEdgeSnapshot(
        sourceNode: sourceNode,
        sourcePort: sourcePort,
        targetNode: targetNode,
        targetPort: targetPort,
      ),
    );
  }

  return ParsedFlowDocument(
    workspaceId: workspaceId,
    docId: docId,
    verId: verId,
    createdAt: createdAt,
    parents: parents,
    title: title,
    nodes: nodes,
    edges: edges,
  );
}

List<FlowPort> _parsePorts(Object? rawPorts) {
  if (rawPorts is! List) {
    return const <FlowPort>[];
  }
  final ports = <FlowPort>[];
  for (final port in rawPorts) {
    if (port is! Map<String, dynamic>) {
      continue;
    }
    final name = port['port'];
    final schema = port['schema'];
    if (name is! String || schema is! String) {
      continue;
    }
    ports.add(FlowPort(port: name, schema: schema));
  }
  return ports;
}
