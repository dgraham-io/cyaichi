String platformDefaultWorkspaceDataRoot() => './workspace-data';

String platformResolveWorkspaceDataRoot(String configuredRoot) =>
    configuredRoot.trim().isEmpty ? './workspace-data' : configuredRoot.trim();
