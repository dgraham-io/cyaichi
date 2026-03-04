import 'dart:io';

String platformDefaultWorkspaceDataRoot() {
  final cwd = Directory.current.path;
  final normalized = cwd.replaceAll('\\', '/');
  if (normalized.endsWith('/client')) {
    return '../workspace-data';
  }
  return './workspace-data';
}

String platformResolveWorkspaceDataRoot(String configuredRoot) {
  final root = configuredRoot.trim().isEmpty
      ? platformDefaultWorkspaceDataRoot()
      : configuredRoot.trim();
  try {
    return Directory(root).absolute.path;
  } catch (_) {
    return root;
  }
}
