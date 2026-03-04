import 'package:client/src/models/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseRunListResponse maps run items', () {
    final parsed = parseRunListResponse(<String, dynamic>{
      'items': [
        <String, dynamic>{
          'doc_id': 'run-1',
          'ver_id': 'ver-1',
          'created_at': '2026-03-04T15:30:00Z',
          'status': 'succeeded',
          'mode': 'hybrid',
        },
        <String, dynamic>{
          'doc_id': 'run-2',
          'ver_id': 'ver-2',
          'created_at': '2026-03-04T16:00:00Z',
          'status': 'failed',
          'mode': 'hybrid',
        },
      ],
    });

    expect(parsed, hasLength(2));
    expect(parsed[0].docId, 'run-1');
    expect(parsed[0].status, 'succeeded');
    expect(parsed[1].docId, 'run-2');
    expect(parsed[1].status, 'failed');
  });
}
