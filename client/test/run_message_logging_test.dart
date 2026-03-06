import 'package:client/messages/message_center.dart';
import 'package:client/src/flow_canvas_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MessageCenter.instance.clear();
  });

  test('run success path logs a success message', () {
    logRunSucceededMessage(
      messageCenter: MessageCenter.instance,
      durationMs: 1234,
      runId: 'run-1',
      runVerId: 'run-ver-1',
      outputPath: '/tmp/output.txt',
      outputArtifactSummary: 'artifact://output',
    );

    final messages = MessageCenter.instance.messages;
    expect(messages, isNotEmpty);
    final latest = messages.first;
    expect(latest.level, AppMessageLevel.success);
    expect(latest.title, 'Run succeeded');
    expect(latest.message, 'Completed in 1234ms');
    expect(latest.details?['run_id'], 'run-1');
    expect(latest.details?['run_ver_id'], 'run-ver-1');
  });

  test('run failure path logs an error message', () {
    logRunFailedMessage(
      messageCenter: MessageCenter.instance,
      message: 'Server execution failed',
      runId: 'run-2',
      runVerId: 'run-ver-2',
      errorKind: 'server',
      nodeId: 'node-123',
      extraDetails: <String, dynamic>{'endpoint': '/v1/runs'},
    );

    final messages = MessageCenter.instance.messages;
    expect(messages, isNotEmpty);
    final latest = messages.first;
    expect(latest.level, AppMessageLevel.error);
    expect(latest.title, 'Run failed');
    expect(latest.message, 'Server execution failed');
    expect(latest.details?['run_id'], 'run-2');
    expect(latest.details?['error_kind'], 'server');
    expect(latest.details?['endpoint'], '/v1/runs');
  });
}
