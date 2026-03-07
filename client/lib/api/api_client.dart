import 'dart:async';
import 'dart:convert';

import 'package:client/src/models/server_models.dart';
import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError({
    required this.message,
    this.statusCode,
    this.isNetwork = false,
    this.isTimeout = false,
    this.timeoutSeconds,
    this.responseBody,
    this.method,
    this.endpoint,
  });

  final String message;
  final int? statusCode;
  final bool isNetwork;
  final bool isTimeout;
  final int? timeoutSeconds;
  final Map<String, dynamic>? responseBody;
  final String? method;
  final String? endpoint;

  @override
  String toString() {
    final endpointPrefix = method != null && endpoint != null
        ? '$method $endpoint: '
        : '';
    if (statusCode != null) {
      return '${endpointPrefix}HTTP $statusCode: $message';
    }
    return '$endpointPrefix$message';
  }
}

class WorkspaceCreated {
  WorkspaceCreated({
    required this.workspaceId,
    required this.docId,
    required this.verId,
  });

  final String workspaceId;
  final String docId;
  final String verId;
}

class WorkspacePatched {
  WorkspacePatched({
    required this.workspaceId,
    required this.verId,
    required this.name,
  });

  final String workspaceId;
  final String verId;
  final String name;
}

class WorkspaceDeleted {
  WorkspaceDeleted({
    required this.workspaceId,
    required this.verId,
    required this.deleted,
  });

  final String workspaceId;
  final String verId;
  final bool deleted;
}

class RunCreated {
  RunCreated({
    required this.runId,
    required this.runVerId,
    this.flowDocId,
    this.flowVerId,
  });

  final String runId;
  final String runVerId;
  final String? flowDocId;
  final String? flowVerId;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.runRequestTimeout = const Duration(seconds: 300),
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final Duration runRequestTimeout;
  final http.Client _httpClient;

  void close() {
    _httpClient.close();
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(normalizedBase).resolve(normalizedPath);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? requestTimeout,
  }) async {
    final uri = _uri(path);
    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.StreamedResponse streamed;
    try {
      streamed = await _httpClient
          .send(request)
          .timeout(requestTimeout ?? timeout);
    } on TimeoutException {
      final timeoutDuration = requestTimeout ?? timeout;
      throw ApiError(
        message: 'request timed out after ${timeoutDuration.inSeconds}s',
        isNetwork: true,
        isTimeout: true,
        timeoutSeconds: timeoutDuration.inSeconds,
        method: method,
        endpoint: path,
      );
    } on http.ClientException catch (error) {
      throw ApiError(
        message: 'server not reachable (${error.message})',
        isNetwork: true,
        method: method,
        endpoint: path,
      );
    }

    final response = await http.Response.fromStream(streamed);
    final payloadText = utf8.decode(response.bodyBytes);
    Map<String, dynamic>? decodedMap;
    if (payloadText.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadText);
        if (decoded is Map<String, dynamic>) {
          decodedMap = decoded;
        }
      } catch (_) {
        decodedMap = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(
        message: _extractErrorMessage(
          decodedMap,
          fallback: payloadText.trim().isEmpty ? 'request failed' : payloadText,
        ),
        statusCode: response.statusCode,
        responseBody: decodedMap,
        method: method,
        endpoint: path,
      );
    }

    return decodedMap ?? <String, dynamic>{};
  }

  String _extractErrorMessage(
    Map<String, dynamic>? map, {
    required String fallback,
  }) {
    if (map == null) {
      return fallback;
    }
    final error = map['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
    final directMessage = map['message'];
    if (directMessage is String && directMessage.trim().isNotEmpty) {
      return directMessage;
    }
    final stringError = map['error'];
    if (stringError is String && stringError.trim().isNotEmpty) {
      return stringError;
    }
    return fallback;
  }

  Future<WorkspaceCreated> createWorkspace({required String name}) async {
    final json = await _requestJson(
      'POST',
      '/v1/workspaces',
      body: <String, dynamic>{'name': name},
    );
    return WorkspaceCreated(
      workspaceId: json['workspace_id'] as String,
      docId: json['doc_id'] as String,
      verId: json['ver_id'] as String,
    );
  }

  Future<List<WorkspaceListItem>> getWorkspaces() async {
    final json = await _requestJson('GET', '/v1/workspaces');
    return parseWorkspaceListResponse(json);
  }

  Future<WorkspacePatched> patchWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/v1/workspaces/$workspaceId',
      body: <String, dynamic>{'name': name},
    );
    return WorkspacePatched(
      workspaceId: json['workspace_id'] as String? ?? workspaceId,
      verId: json['ver_id'] as String? ?? '',
      name: json['name'] as String? ?? name,
    );
  }

  Future<WorkspaceDeleted> deleteWorkspace({
    required String workspaceId,
  }) async {
    final json = await _requestJson('DELETE', '/v1/workspaces/$workspaceId');
    return WorkspaceDeleted(
      workspaceId: json['workspace_id'] as String? ?? workspaceId,
      verId: json['ver_id'] as String? ?? '',
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  Future<void> putFlowDocument({
    required String docId,
    required String verId,
    required Map<String, dynamic> document,
  }) async {
    await _requestJson('PUT', '/v1/docs/flow/$docId/$verId', body: document);
  }

  Future<void> putDocument({
    required String docType,
    required String docId,
    required String verId,
    required Map<String, dynamic> document,
  }) async {
    await _requestJson(
      'PUT',
      '/v1/docs/$docType/$docId/$verId',
      body: document,
    );
  }

  Future<void> setHead({
    required String workspaceId,
    required String docId,
    required String verId,
  }) async {
    await _requestJson(
      'PUT',
      '/v1/workspaces/$workspaceId/heads/$docId',
      body: <String, dynamic>{'ver_id': verId},
    );
  }

  Future<RunCreated> createRun({
    required String workspaceId,
    required String flowDocId,
    required String inputFile,
    required String outputFile,
  }) async {
    final json = await _requestJson(
      'POST',
      '/v1/runs',
      body: <String, dynamic>{
        'workspace_id': workspaceId,
        'flow_ref': <String, dynamic>{
          'doc_id': flowDocId,
          'ver_id': null,
          'selector': 'head',
        },
        'inputs': <String, dynamic>{
          'input_file': inputFile,
          'output_file': outputFile,
        },
      },
      requestTimeout: runRequestTimeout,
    );

    final flow = json['flow'];
    return RunCreated(
      runId: json['run_id'] as String,
      runVerId: json['run_ver_id'] as String,
      flowDocId: flow is Map<String, dynamic>
          ? flow['doc_id'] as String?
          : null,
      flowVerId: flow is Map<String, dynamic>
          ? flow['ver_id'] as String?
          : null,
    );
  }

  Future<Map<String, dynamic>> getDocument({
    required String docType,
    required String docId,
    required String verId,
  }) async {
    return _requestJson('GET', '/v1/docs/$docType/$docId/$verId');
  }

  Future<List<RunListItem>> getRuns({required String workspaceId}) async {
    final json = await _requestJson('GET', '/v1/workspaces/$workspaceId/runs');
    return parseRunListResponse(json);
  }

  Future<List<FlowListItem>> getFlows({required String workspaceId}) async {
    final json = await _requestJson('GET', '/v1/workspaces/$workspaceId/flows');
    return parseFlowListResponse(json);
  }

  Future<List<NodeTypeDef>> getNodeTypes() async {
    final json = await _requestJson('GET', '/v1/node-types');
    return parseNodeTypeListResponse(json);
  }

  Future<Map<String, dynamic>> getRun({
    required String docId,
    required String verId,
  }) async {
    return getDocument(docType: 'run', docId: docId, verId: verId);
  }

  Future<List<ChannelListItem>> getChannels({
    required String workspaceId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/v1/workspaces/$workspaceId/channels',
    );
    return parseChannelListResponse(json);
  }

  Future<MemoryCreated> createChannel({
    required String workspaceId,
    required String scope,
    required String name,
    required String kind,
    String? topic,
    String? flowDocId,
    String? flowVerId,
    String? flowTitle,
    String createdByKind = 'user',
    String createdById = 'local-user',
    String createdByLabel = 'You',
  }) async {
    final json = await _requestJson(
      'POST',
      '/v1/channels',
      body: <String, dynamic>{
        'workspace_id': workspaceId,
        'scope': scope,
        'name': name,
        'kind': kind,
        'topic': topic ?? '',
        'flow_doc_id': flowDocId ?? '',
        'flow_ver_id': flowVerId ?? '',
        'flow_title': flowTitle ?? '',
        'created_by': <String, dynamic>{
          'kind': createdByKind,
          'id': createdById,
          'label': createdByLabel,
        },
      },
    );
    return MemoryCreated(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
    );
  }

  Future<List<MessageListItem>> getMessages({
    required String channelDocId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/v1/channels/$channelDocId/messages',
    );
    return parseMessageListResponse(json);
  }

  Future<MemoryCreated> createMessage({
    required String workspaceId,
    required String scope,
    required String channelDocId,
    required String body,
    String format = 'markdown',
    String authorKind = 'user',
    String authorId = 'local-user',
    String authorLabel = 'You',
    List<CollaborationRef> refs = const <CollaborationRef>[],
  }) async {
    final json = await _requestJson(
      'POST',
      '/v1/messages',
      body: <String, dynamic>{
        'workspace_id': workspaceId,
        'scope': scope,
        'channel_doc_id': channelDocId,
        'format': format,
        'body': body,
        'author': <String, dynamic>{
          'kind': authorKind,
          'id': authorId,
          'label': authorLabel,
        },
        'refs': refs.map((item) => item.toJson()).toList(growable: false),
      },
    );
    return MemoryCreated(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
    );
  }

  Future<List<NoteListItem>> getNotes({required String workspaceId}) async {
    final json = await _requestJson('GET', '/v1/workspaces/$workspaceId/notes');
    return parseNoteListResponse(json);
  }

  Future<NoteCreated> createNote({
    required String workspaceId,
    required String scope,
    required String title,
    required String body,
  }) async {
    final json = await _requestJson(
      'POST',
      '/v1/notes',
      body: <String, dynamic>{
        'workspace_id': workspaceId,
        'scope': scope,
        'title': title,
        'body': body,
      },
    );
    return NoteCreated(
      docId: json['doc_id'] as String? ?? '',
      verId: json['ver_id'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> getNote({
    required String docId,
    required String verId,
  }) async {
    return _requestJson('GET', '/v1/notes/$docId/$verId');
  }
}
