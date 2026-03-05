class ArtifactRefId {
  const ArtifactRefId({required this.docId, required this.verId});

  final String docId;
  final String verId;

  bool matches(ArtifactRefId other) {
    return docId == other.docId && verId == other.verId;
  }
}

class ResolvedRunOutputArtifact {
  const ResolvedRunOutputArtifact({
    required this.ref,
    required this.schema,
    required this.path,
    required this.bytes,
  });

  final ArtifactRefId ref;
  final String schema;
  final String? path;
  final int? bytes;

  String get summary {
    final buffer = StringBuffer(schema.isEmpty ? 'artifact' : schema);
    if (path != null && path!.isNotEmpty) {
      buffer.write(' • path=$path');
    }
    if (bytes != null) {
      buffer.write(' • bytes=$bytes');
    }
    return buffer.toString();
  }
}

class RunOutputResolution {
  const RunOutputResolution({
    required this.outputArtifacts,
    this.previewText,
    this.fallbackMessage,
  });

  final List<ResolvedRunOutputArtifact> outputArtifacts;
  final String? previewText;
  final String? fallbackMessage;
}

typedef FetchArtifactDocument =
    Future<Map<String, dynamic>> Function({
      required String docId,
      required String verId,
    });

Future<RunOutputResolution> resolveRunOutputs({
  required Map<String, dynamic>? runBody,
  required FetchArtifactDocument fetchArtifactDocument,
}) async {
  if (runBody == null) {
    return const RunOutputResolution(
      outputArtifacts: <ResolvedRunOutputArtifact>[],
    );
  }

  final outputRefs = _artifactRefsFromRunOutputs(runBody['outputs']);
  final outputArtifacts = <ResolvedRunOutputArtifact>[];
  String? previewText;

  for (final ref in outputRefs) {
    final artifactDoc = await fetchArtifactDocument(
      docId: ref.docId,
      verId: ref.verId,
    );
    final body = artifactDoc['body'];
    if (body is! Map<String, dynamic>) {
      continue;
    }
    final schema = body['schema'] as String? ?? '';
    final payload = body['payload'];
    final payloadMap = payload is Map<String, dynamic>
        ? payload
        : const <String, dynamic>{};
    final path = payloadMap['path'] as String?;
    final bytesRaw = payloadMap['bytes'];
    final bytes = bytesRaw is int
        ? bytesRaw
        : (bytesRaw is num ? bytesRaw.toInt() : null);
    outputArtifacts.add(
      ResolvedRunOutputArtifact(
        ref: ref,
        schema: schema,
        path: path,
        bytes: bytes,
      ),
    );

    if (previewText == null && schema == 'artifact/output_file') {
      final upstreamTextRef = _findUpstreamInputRefForOutput(runBody, ref);
      if (upstreamTextRef != null) {
        final upstreamDoc = await fetchArtifactDocument(
          docId: upstreamTextRef.docId,
          verId: upstreamTextRef.verId,
        );
        final upstreamBody = upstreamDoc['body'];
        if (upstreamBody is Map<String, dynamic>) {
          final upstreamSchema = upstreamBody['schema'] as String? ?? '';
          final upstreamPayload = upstreamBody['payload'];
          if (upstreamSchema == 'artifact/text' &&
              upstreamPayload is Map<String, dynamic>) {
            final text = upstreamPayload['text'];
            if (text is String && text.trim().isNotEmpty) {
              previewText = text;
            }
          }
        }
      }
    }
  }

  String? fallbackMessage;
  if (previewText == null) {
    final firstPath = outputArtifacts
        .map((item) => item.path)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (firstPath.isNotEmpty) {
      fallbackMessage =
          'Run succeeded. Output file is on server at $firstPath. Configure workspace root or enable server file download.';
    }
  }

  return RunOutputResolution(
    outputArtifacts: outputArtifacts,
    previewText: previewText,
    fallbackMessage: fallbackMessage,
  );
}

List<ArtifactRefId> _artifactRefsFromRunOutputs(Object? rawOutputs) {
  if (rawOutputs is! List<dynamic>) {
    return const <ArtifactRefId>[];
  }
  final refs = <ArtifactRefId>[];
  for (final item in rawOutputs) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final refRaw = item['artifact_ref'];
    final refMap = refRaw is Map<String, dynamic> ? refRaw : item;
    final ref = _parseArtifactRef(refMap);
    if (ref != null) {
      refs.add(ref);
    }
  }
  return refs;
}

ArtifactRefId? _findUpstreamInputRefForOutput(
  Map<String, dynamic> runBody,
  ArtifactRefId outputRef,
) {
  final invocations = runBody['invocations'];
  if (invocations is! List<dynamic>) {
    return null;
  }

  for (final raw in invocations) {
    if (raw is! Map<String, dynamic>) {
      continue;
    }
    final outputs = raw['outputs'];
    final outputRefs = _artifactRefsFromRunOutputs(outputs);
    final hasOutput = outputRefs.any((item) => item.matches(outputRef));
    if (!hasOutput) {
      continue;
    }
    final inputs = raw['inputs'];
    if (inputs is! List<dynamic>) {
      continue;
    }
    for (final input in inputs) {
      if (input is! Map<String, dynamic>) {
        continue;
      }
      final refRaw = input['artifact_ref'];
      final refMap = refRaw is Map<String, dynamic> ? refRaw : input;
      final parsed = _parseArtifactRef(refMap);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

ArtifactRefId? _parseArtifactRef(Map<String, dynamic> raw) {
  final docId = raw['doc_id'];
  final verId = raw['ver_id'];
  if (docId is! String || docId.trim().isEmpty) {
    return null;
  }
  if (verId is! String || verId.trim().isEmpty) {
    return null;
  }
  return ArtifactRefId(docId: docId, verId: verId);
}
