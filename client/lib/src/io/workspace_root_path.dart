import 'workspace_root_path_stub.dart'
    if (dart.library.io) 'workspace_root_path_io.dart';

String defaultWorkspaceDataRoot() => platformDefaultWorkspaceDataRoot();

String resolveWorkspaceDataRoot(String configuredRoot) =>
    platformResolveWorkspaceDataRoot(configuredRoot);
