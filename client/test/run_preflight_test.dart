import 'package:client/src/flow/run_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run preflight does not save when flow is not dirty', () async {
    var saveCalls = 0;
    final decision = await ensureFlowSavedForRun(
      isFlowDirty: false,
      saveNewVersion: () async {
        saveCalls += 1;
        return true;
      },
    );

    expect(saveCalls, 0);
    expect(decision.shouldContinue, isTrue);
    expect(decision.didSaveNewVersion, isFalse);
    expect(decision.errorMessage, isNull);
  });

  test('run preflight saves exactly once when flow is dirty', () async {
    var saveCalls = 0;
    final decision = await ensureFlowSavedForRun(
      isFlowDirty: true,
      saveNewVersion: () async {
        saveCalls += 1;
        return true;
      },
    );

    expect(saveCalls, 1);
    expect(decision.shouldContinue, isTrue);
    expect(decision.didSaveNewVersion, isTrue);
    expect(decision.errorMessage, isNull);
  });
}
