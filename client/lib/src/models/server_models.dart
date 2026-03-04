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
