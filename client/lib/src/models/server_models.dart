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

class CollaborationRef {
  CollaborationRef({
    required this.kind,
    this.id,
    this.label,
    this.docId,
    this.verId,
    this.selector,
    this.nodeId,
    this.flowDocId,
    this.flowVerId,
  });

  final String kind;
  final String? id;
  final String? label;
  final String? docId;
  final String? verId;
  final String? selector;
  final String? nodeId;
  final String? flowDocId;
  final String? flowVerId;

  factory CollaborationRef.fromJson(Map<String, dynamic> json) {
    return CollaborationRef(
      kind: json['kind'] as String? ?? '',
      id: json['id'] as String?,
      label: json['label'] as String?,
      docId: json['doc_id'] as String?,
      verId: json['ver_id'] as String?,
      selector: json['selector'] as String?,
      nodeId: json['node_id'] as String?,
      flowDocId: json['flow_doc_id'] as String?,
      flowVerId: json['flow_ver_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'kind': kind};
    if (id != null && id!.trim().isNotEmpty) {
      json['id'] = id;
    }
    if (label != null && label!.trim().isNotEmpty) {
      json['label'] = label;
    }
    if (docId != null && docId!.trim().isNotEmpty) {
      json['doc_id'] = docId;
    }
    if (verId != null && verId!.trim().isNotEmpty) {
      json['ver_id'] = verId;
    }
    if (selector != null && selector!.trim().isNotEmpty) {
      json['selector'] = selector;
    }
    if (nodeId != null && nodeId!.trim().isNotEmpty) {
      json['node_id'] = nodeId;
    }
    if (flowDocId != null && flowDocId!.trim().isNotEmpty) {
      json['flow_doc_id'] = flowDocId;
    }
    if (flowVerId != null && flowVerId!.trim().isNotEmpty) {
      json['flow_ver_id'] = flowVerId;
    }
    return json;
  }

  String get displayLabel {
    final trimmedLabel = label?.trim() ?? '';
    if (trimmedLabel.isNotEmpty) {
      return trimmedLabel;
    }
    final trimmedId = id?.trim() ?? '';
    if (trimmedId.isNotEmpty) {
      return trimmedId;
    }
    final trimmedDocId = docId?.trim() ?? '';
    if (trimmedDocId.isNotEmpty) {
      return trimmedDocId;
    }
    final trimmedNodeId = nodeId?.trim() ?? '';
    if (trimmedNodeId.isNotEmpty) {
      return trimmedNodeId;
    }
    return kind;
  }
}

class ChannelListItem {
  ChannelListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.name,
    required this.scope,
    required this.kind,
    required this.topic,
    required this.flowDocId,
    required this.flowVerId,
    required this.flowTitle,
    required this.isArchived,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String name;
  final String scope;
  final String kind;
  final String topic;
  final String flowDocId;
  final String flowVerId;
  final String flowTitle;
  final bool isArchived;

  factory ChannelListItem.fromJson(Map<String, dynamic> json) {
    return ChannelListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      name: json['name'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      topic: json['topic'] as String? ?? '',
      flowDocId: json['flow_doc_id'] as String? ?? '',
      flowVerId: json['flow_ver_id'] as String? ?? '',
      flowTitle: json['flow_title'] as String? ?? '',
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }
}

class MessageListItem {
  MessageListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.body,
    required this.format,
    required this.authorKind,
    required this.authorId,
    required this.authorLabel,
    required this.refs,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String body;
  final String format;
  final String authorKind;
  final String authorId;
  final String authorLabel;
  final List<CollaborationRef> refs;

  factory MessageListItem.fromJson(Map<String, dynamic> json) {
    final rawRefs = json['refs'];
    return MessageListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      body: json['body'] as String? ?? '',
      format: json['format'] as String? ?? 'markdown',
      authorKind: json['author_kind'] as String? ?? 'user',
      authorId: json['author_id'] as String? ?? '',
      authorLabel: json['author_label'] as String? ?? '',
      refs: rawRefs is List<dynamic>
          ? rawRefs
                .whereType<Map<String, dynamic>>()
                .map(CollaborationRef.fromJson)
                .toList(growable: false)
          : const <CollaborationRef>[],
    );
  }
}

class TaskListItem {
  TaskListItem({
    required this.docId,
    required this.verId,
    required this.createdAt,
    required this.title,
    required this.bodyPreview,
    required this.scope,
    required this.status,
    required this.channelDocId,
    required this.assigneeLabel,
    required this.refs,
  });

  final String docId;
  final String verId;
  final String createdAt;
  final String title;
  final String bodyPreview;
  final String scope;
  final String status;
  final String channelDocId;
  final String assigneeLabel;
  final List<CollaborationRef> refs;

  factory TaskListItem.fromJson(Map<String, dynamic> json) {
    final rawRefs = json['refs'];
    return TaskListItem(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      title: json['title'] as String? ?? '',
      bodyPreview: json['body_preview'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      channelDocId: json['channel_doc_id'] as String? ?? '',
      assigneeLabel: json['assignee_label'] as String? ?? '',
      refs: rawRefs is List<dynamic>
          ? rawRefs
                .whereType<Map<String, dynamic>>()
                .map(CollaborationRef.fromJson)
                .toList(growable: false)
          : const <CollaborationRef>[],
    );
  }
}

class MemoryCreated {
  MemoryCreated({required this.docId, required this.verId});

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

class WorkspaceListItem {
  WorkspaceListItem({
    required this.workspaceId,
    required this.name,
    required this.createdAt,
  });

  final String workspaceId;
  final String name;
  final String createdAt;

  factory WorkspaceListItem.fromJson(Map<String, dynamic> json) {
    return WorkspaceListItem(
      workspaceId: json['workspace_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
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

List<WorkspaceListItem> parseWorkspaceListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <WorkspaceListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(WorkspaceListItem.fromJson)
      .where((item) => item.workspaceId.isNotEmpty)
      .toList(growable: false);
}

List<ChannelListItem> parseChannelListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <ChannelListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(ChannelListItem.fromJson)
      .where((item) => item.docId.isNotEmpty && item.verId.isNotEmpty)
      .toList(growable: false);
}

List<MessageListItem> parseMessageListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <MessageListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(MessageListItem.fromJson)
      .where((item) => item.docId.isNotEmpty && item.verId.isNotEmpty)
      .toList(growable: false);
}

List<TaskListItem> parseTaskListResponse(Map<String, dynamic> json) {
  final rawItems = json['items'];
  if (rawItems is! List<dynamic>) {
    return const <TaskListItem>[];
  }

  return rawItems
      .whereType<Map<String, dynamic>>()
      .map(TaskListItem.fromJson)
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
