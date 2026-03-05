class RunFlowSaveDecision {
  const RunFlowSaveDecision({
    required this.shouldContinue,
    required this.didSaveNewVersion,
    this.errorMessage,
  });

  final bool shouldContinue;
  final bool didSaveNewVersion;
  final String? errorMessage;
}

Future<RunFlowSaveDecision> ensureFlowSavedForRun({
  required bool isFlowDirty,
  required Future<bool> Function() saveNewVersion,
}) async {
  if (!isFlowDirty) {
    return const RunFlowSaveDecision(
      shouldContinue: true,
      didSaveNewVersion: false,
    );
  }

  final saved = await saveNewVersion();
  if (!saved) {
    return const RunFlowSaveDecision(
      shouldContinue: false,
      didSaveNewVersion: false,
      errorMessage: 'Flow save failed; run aborted.',
    );
  }

  return const RunFlowSaveDecision(
    shouldContinue: true,
    didSaveNewVersion: true,
  );
}
