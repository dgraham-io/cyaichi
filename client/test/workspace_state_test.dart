import 'package:client/src/models/server_models.dart';
import 'package:client/src/workspaces/workspace_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dedupeWorkspaceItemsByID returns unique workspace IDs', () {
    final input = <WorkspaceListItem>[
      WorkspaceListItem(
        workspaceId: 'ws-1',
        name: 'One',
        createdAt: '2026-03-04T10:00:00Z',
      ),
      WorkspaceListItem(
        workspaceId: 'ws-1',
        name: 'One duplicate',
        createdAt: '2026-03-04T09:00:00Z',
      ),
      WorkspaceListItem(
        workspaceId: 'ws-2',
        name: 'Two',
        createdAt: '2026-03-04T08:00:00Z',
      ),
    ];

    final deduped = dedupeWorkspaceItemsByID(input);
    expect(deduped, hasLength(2));
    expect(deduped[0].workspaceId, 'ws-1');
    expect(deduped[1].workspaceId, 'ws-2');
  });

  test(
    'resolveWorkspaceDropdownValue returns null when selected id missing',
    () {
      final value = resolveWorkspaceDropdownValue(
        workspaceIDs: const <String>[],
        selectedWorkspaceID: 'missing',
      );
      expect(value, isNull);
    },
  );
}
