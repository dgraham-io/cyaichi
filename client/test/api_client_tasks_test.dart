import 'dart:convert';

import 'package:client/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _CapturingClient extends http.BaseClient {
  _CapturingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return handler(request);
  }
}

http.StreamedResponse _jsonResponse(int statusCode, Map<String, dynamic> body) {
  final payload = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(payload),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

void main() {
  test('getTasks parses task list response', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: _CapturingClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/workspaces/ws-1/tasks');
        return _jsonResponse(200, <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'doc_id': 'task-1',
              'ver_id': 'ver-1',
              'created_at': '2026-03-08T12:00:00Z',
              'title': 'Review prompt',
              'body_preview': 'Check the prompt',
              'scope': 'team',
              'status': 'open',
              'assignee_label': 'Planner Agent',
            },
          ],
        });
      }),
    );

    final tasks = await api.getTasks(workspaceId: 'ws-1');
    api.close();

    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Review prompt');
    expect(tasks.single.assigneeLabel, 'Planner Agent');
  });

  test('createTask posts expected payload', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: _CapturingClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/tasks');

        final typed = request as http.Request;
        final body = jsonDecode(typed.body) as Map<String, dynamic>;
        expect(body['workspace_id'], 'ws-1');
        expect(body['scope'], 'team');
        expect(body['channel_doc_id'], 'channel-1');
        expect(body['title'], 'Review prompt');
        expect(body['status'], 'open');
        expect(body['created_by'], <String, dynamic>{
          'kind': 'user',
          'id': 'user-1',
          'label': 'Dana',
        });
        expect(body['assignee'], <String, dynamic>{
          'kind': 'agent',
          'id': 'planner',
          'label': 'Planner Agent',
        });

        return _jsonResponse(201, <String, dynamic>{
          'doc_id': 'task-1',
          'ver_id': 'ver-1',
        });
      }),
    );

    final created = await api.createTask(
      workspaceId: 'ws-1',
      scope: 'team',
      channelDocId: 'channel-1',
      title: 'Review prompt',
      body: 'Check the processor prompt',
      createdById: 'user-1',
      createdByLabel: 'Dana',
      assigneeKind: 'agent',
      assigneeId: 'planner',
      assigneeLabel: 'Planner Agent',
    );
    api.close();

    expect(created.docId, 'task-1');
    expect(created.verId, 'ver-1');
  });

  test('patchTask posts status update', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: _CapturingClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v1/tasks/task-1');

        final typed = request as http.Request;
        final body = jsonDecode(typed.body) as Map<String, dynamic>;
        expect(body, <String, dynamic>{'status': 'done'});

        return _jsonResponse(200, <String, dynamic>{
          'doc_id': 'task-1',
          'ver_id': 'ver-2',
        });
      }),
    );

    final updated = await api.patchTask(taskDocId: 'task-1', status: 'done');
    api.close();

    expect(updated.docId, 'task-1');
    expect(updated.verId, 'ver-2');
  });
}
