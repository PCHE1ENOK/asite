import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openSettings(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Настройки'));
    await UiHarness.settle(tester);
  }

  testWidgets('18+ switch updates the shared setting', (tester) async {
    await openSettings(tester);
    expect(find.text('Вход не выполнен'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await UiHarness.settle(tester);
    expect(h.settings.showAdult, isFalse);
    expect(await tester.runAsync(h.services.preferences.showAdult), isFalse);
    await h.dispose(tester);
  });

  testWidgets('theme segments switch theme mode', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('Светлая'));
    await UiHarness.settle(tester);
    expect(h.settings.theme, ThemePreference.light);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    await h.dispose(tester);
  });
}
