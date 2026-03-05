import 'package:client/src/models/server_models.dart';

List<WorkspaceListItem> dedupeWorkspaceItemsByID(
  List<WorkspaceListItem> items,
) {
  final seen = <String>{};
  final deduped = <WorkspaceListItem>[];
  for (final item in items) {
    final id = item.workspaceId.trim();
    if (id.isEmpty || seen.contains(id)) {
      continue;
    }
    seen.add(id);
    deduped.add(item);
  }
  return deduped;
}

String? resolveWorkspaceDropdownValue({
  required List<String> workspaceIDs,
  required String? selectedWorkspaceID,
}) {
  if (selectedWorkspaceID == null || selectedWorkspaceID.trim().isEmpty) {
    return null;
  }
  var matches = 0;
  for (final id in workspaceIDs) {
    if (id == selectedWorkspaceID) {
      matches += 1;
      if (matches > 1) {
        return null;
      }
    }
  }
  return matches == 1 ? selectedWorkspaceID : null;
}
