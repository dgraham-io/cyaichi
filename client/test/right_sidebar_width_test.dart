import 'package:client/src/flow_canvas_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('clamps sidebar width to min and max bounds', () {
    expect(clampRightOverlaySidebarWidth(120, 1400), 280);
    expect(clampRightOverlaySidebarWidth(900, 1400), 520);
  });

  test('persists and restores sidebar width value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('client.right_overlay_sidebar_width', 432);

    final stored = prefs.getDouble('client.right_overlay_sidebar_width');
    expect(stored, isNotNull);
    expect(clampRightOverlaySidebarWidth(stored!, 1600), 432);
  });
}
