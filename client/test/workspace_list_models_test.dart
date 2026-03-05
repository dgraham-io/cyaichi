import 'package:client/src/models/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseWorkspaceListResponse maps workspace items', () {
    final parsed = parseWorkspaceListResponse(<String, dynamic>{
      'items': [
        <String, dynamic>{
          'workspace_id': 'ws-1',
          'name': 'Workspace One',
          'created_at': '2026-03-04T10:00:00Z',
        },
        <String, dynamic>{
          'workspace_id': 'ws-2',
          'name': 'Workspace Two',
          'created_at': '2026-03-04T11:00:00Z',
        },
      ],
    });

    expect(parsed, hasLength(2));
    expect(parsed[0].workspaceId, 'ws-1');
    expect(parsed[0].name, 'Workspace One');
    expect(parsed[1].workspaceId, 'ws-2');
    expect(parsed[1].name, 'Workspace Two');
  });
}
