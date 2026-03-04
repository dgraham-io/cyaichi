class WriteNodeOption {
  const WriteNodeOption({
    required this.nodeId,
    required this.title,
    required this.outputFile,
    required this.isPrimary,
  });

  final String nodeId;
  final String title;
  final String outputFile;
  final bool isPrimary;

  WriteNodeOption copyWith({
    String? nodeId,
    String? title,
    String? outputFile,
    bool? isPrimary,
  }) {
    return WriteNodeOption(
      nodeId: nodeId ?? this.nodeId,
      title: title ?? this.title,
      outputFile: outputFile ?? this.outputFile,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

List<WriteNodeOption> setPrimaryWriteNode(
  List<WriteNodeOption> writes,
  String primaryNodeId,
) {
  return writes
      .map((write) => write.copyWith(isPrimary: write.nodeId == primaryNodeId))
      .toList(growable: false);
}

String? chooseRunOutputFile({
  required List<WriteNodeOption> writes,
  String? primaryNodeId,
}) {
  if (writes.isEmpty) {
    return null;
  }

  if (primaryNodeId != null) {
    for (final write in writes) {
      if (write.nodeId == primaryNodeId) {
        final output = write.outputFile.trim();
        return output.isEmpty ? null : output;
      }
    }
  }

  final primaryFromConfig = writes.where((write) => write.isPrimary).toList();
  if (primaryFromConfig.length == 1) {
    final output = primaryFromConfig.first.outputFile.trim();
    return output.isEmpty ? null : output;
  }

  if (writes.length == 1) {
    final output = writes.first.outputFile.trim();
    return output.isEmpty ? null : output;
  }

  return null;
}

String? choosePrimaryWriteNodeId({
  required List<WriteNodeOption> writes,
  String? preferredPrimaryNodeId,
}) {
  if (writes.isEmpty) {
    return null;
  }

  if (preferredPrimaryNodeId != null) {
    for (final write in writes) {
      if (write.nodeId == preferredPrimaryNodeId) {
        return write.nodeId;
      }
    }
  }

  final primaryFromConfig = writes.where((write) => write.isPrimary).toList();
  if (primaryFromConfig.length == 1) {
    return primaryFromConfig.first.nodeId;
  }

  if (writes.length == 1) {
    return writes.first.nodeId;
  }

  return null;
}
