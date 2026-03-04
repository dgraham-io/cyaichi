import 'dart:async';
import 'dart:convert';

import 'package:client/src/models/server_models.dart';
import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError({
    required this.message,
    this.statusCode,
    this.isNetwork = false,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final bool isNetwork;
  final Map<String, dynamic>? responseBody;

  @override
  String toString() {
    if (statusCode != null) {
      return 'HTTP $statusCode: $message';
    }
    return message;
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
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
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
  }) async {
    final uri = _uri(path);
    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';
    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(timeout);
    } on TimeoutException {
      throw ApiError(
        message: 'server not reachable (request timeout)',
        isNetwork: true,
      );
    } on http.ClientException catch (error) {
      throw ApiError(
        message: 'server not reachable (${error.message})',
        isNetwork: true,
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

  Future<void> putFlowDocument({
    required String docId,
    required String verId,
    required Map<String, dynamic> document,
  }) async {
    await _requestJson('PUT', '/v1/docs/flow/$docId/$verId', body: document);
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
