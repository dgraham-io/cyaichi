import 'dart:async';
import 'dart:convert';

import 'package:client/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

class _DelayedClient extends http.BaseClient {
  _DelayedClient(this.delay);

  final Duration delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(delay);
    final payload = utf8.encode(
      jsonEncode(<String, dynamic>{
        'run_id': '11111111-1111-1111-1111-111111111111',
        'run_ver_id': '22222222-2222-2222-2222-222222222222',
      }),
    );
    return http.StreamedResponse(Stream<List<int>>.value(payload), 201);
  }
}

void main() {
  test('createRun uses configured runRequestTimeout', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: _DelayedClient(const Duration(seconds: 2)),
      timeout: const Duration(seconds: 15),
      runRequestTimeout: const Duration(seconds: 1),
    );

    final watch = Stopwatch()..start();
    ApiError? timeoutError;
    try {
      await api.createRun(
        workspaceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        flowDocId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        inputFile: 'input.txt',
        outputFile: 'output.txt',
      );
    } on ApiError catch (error) {
      timeoutError = error;
    } finally {
      api.close();
    }
    watch.stop();

    expect(timeoutError, isNotNull);
    expect(timeoutError!.isTimeout, isTrue);
    expect(timeoutError.timeoutSeconds, 1);
    expect(timeoutError.method, 'POST');
    expect(timeoutError.endpoint, '/v1/runs');
    expect(watch.elapsed.inSeconds, lessThan(5));
  });
}
