class RunListItem {
  RunListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.status,
    required this.mode,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String status;
  final String mode;

  factory RunListItem.fromJson(Map<String, dynamic> json) {
    return RunListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      mode: json['mode'] as String? ?? '',
    );
  }
}

class NoteListItem {
  NoteListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.title,
    required this.scope,
    required this.bodyPreview,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String title;
  final String scope;
  final String bodyPreview;

  factory NoteListItem.fromJson(Map<String, dynamic> json) {
    return NoteListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      title: json['title'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      bodyPreview: json['body_preview'] as String? ?? '',
    );
  }
}

class NoteCreated {
  NoteCreated({required this.docId, required this.verId});

  final String docId;
  final String verId;
}

class FlowListItem {
  FlowListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.ref,
    required this.title,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String ref;
  final String title;

  factory FlowListItem.fromJson(Map<String, dynamic> json) {
    return FlowListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}

class NodeTypePortDef {
  NodeTypePortDef({required this.port, required this.schema});

  final String port;
  final String schema;

  factory NodeTypePortDef.fromJson(Map<String, dynamic> json) {
    return NodeTypePortDef(
      port: json['port'] as String? ?? '',
      schema: json['schema'] as String? ?? '',
    );
  }
}

class NodeTypeConfigFieldDef {
  NodeTypeConfigFieldDef({
    required this.key,
    required this.kind,
    required this.required,
    required this.label,
  });

  final String key;
  final String kind;
  final bool required;
  final String label;

  factory NodeTypeConfigFieldDef.fromJson(Map<String, dynamic> json) {
    return NodeTypeConfigFieldDef(
      key: json['key'] as String? ?? '',
      kind: json['kind'] as String? ?? 'string',
      required: json['required'] as bool? ?? false,
      label: json['label'] as String? ?? '',
    );
  }
}

class NodeTypeDef {
  NodeTypeDef({
    required this.type,
    required this.displayName,
    required this.category,
    required this.inputs,
    required this.outputs,
    required this.configSchema,
  });

  final String type;
  final String displayName;
  final String category;
  final List<NodeTypePortDef> inputs;
  final List<NodeTypePortDef> outputs;
  final List<NodeTypeConfigFieldDef> configSchema;

  factory NodeTypeDef.fromJson(Map<String, dynamic> json) {
    final rawInputs = json['inputs'];
    final rawOutputs = json['outputs'];
    final rawConfigSchema = json['config_schema'];

    return NodeTypeDef(
      type: json['type'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      inputs: rawInputs is List<dynamic>
          ? rawInputs
                .whereType<Map<String, dynamic>>()
                .map(NodeTypePortDef.fromJson)
                .toList(growable: false)
          : const <NodeTypePortDef>[],
      outputs: rawOutputs is List<dynamic>
          ? rawOutputs
                .whereType<Map<String, dynamic>>()
                .map(NodeTypePortDef.fromJson)
                .toList(growable: false)
          : const <NodeTypePortDef>[],
      configSchema: rawConfigSchema is List<dynamic>
          ? rawConfigSchema
                .whereType<Map<String, dynamic>>()
                .map(NodeTypeConfigFieldDef.fromJson)
                .toList(growable: false)
          : const <NodeTypeConfigFieldDef>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'display_name': displayName,
      'category': category,
      'inputs': inputs
          .map(
            (item) => <String, dynamic>{
              'port': item.port,
              'schema': item.schema,
            },
          )
          .toList(growable: false),
      'outputs': outputs
          .map(
            (item) => <String, dynamic>{
              'port': item.port,
              'schema': item.schema,
            },
          )
          .toList(growable: false),
      'config_schema': configSchema
          .map(
            (item) => <String, dynamic>{
              'key': item.key,
              'kind': item.kind,
              'required': item.required,
              'label': item.label,
            },
          )
          .toList(growable: false),
    };
  }
}

List<RunListItem> parseRunListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <RunListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(RunListItem.fromJson)
      .where((item) => item.docId.isNotEmpty && item.verId.isNotEmpty)
      .toList(growable: false);
}

List<NoteListItem> parseNoteListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <NoteListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(NoteListItem.fromJson)
      .where((item) => item.docId.isNotEmpty && item.verId.isNotEmpty)
      .toList(growable: false);
}

List<FlowListItem> parseFlowListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <FlowListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(FlowListItem.fromJson)
      .where((item) => item.docId.isNotEmpty && item.verId.isNotEmpty)
      .toList(growable: false);
}

List<NodeTypeDef> parseNodeTypeListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <NodeTypeDef>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(NodeTypeDef.fromJson)
      .where((item) => item.type.isNotEmpty && item.displayName.isNotEmpty)
      .toList(growable: false);
}
