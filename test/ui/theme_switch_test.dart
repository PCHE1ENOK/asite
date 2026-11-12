import 'dart:math' as math;

import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:anime_viewer/ui/theme/app_tokens.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = lum(a), y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Цвета всех текстов на экране (включая вложенные TextSpan).
List<Color> textColors(WidgetTester tester, Finder within) {
  final colors = <Color>[];
  for (final e
      in find
          .descendant(of: within, matching: find.byType(RichText))
          .evaluate()) {
    final r = e.renderObject;
    if (r is! RenderParagraph) continue;
    r.text.visitChildren((span) {
      if (span.style?.color case final c?) colors.add(c);
      return true;
    });
  }
  return colors;
}

void main() {
  const light = AppTokens.light;
  const dark = AppTokens.dark;
  final darkText = {dark.fg, dark.fg2, dark.fg3};

  testWidgets('dark → light at runtime: every tab repaints in light tokens', (
    tester,
  ) async {
    final h = UiHarness();
    await tester.runAsync(
      () => h.services.preferences.setTheme(ThemePreference.dark),
    );
    await h.pump(tester, size: const Size(1280, 800));
    // Открываем все вкладки в тёмной теме — их маршруты создаются сейчас.
    for (final tab in ['Списки', 'Поиск', 'Настройки', 'Каталог']) {
      await tester.tap(find.text(tab).first);
      await UiHarness.settle(tester);
    }
    await tester.runAsync(() => h.settings.setTheme(ThemePreference.light));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    for (final tab in ['Каталог', 'Списки', 'Поиск', 'Настройки']) {
      await tester.tap(find.text(tab).first);
      await UiHarness.settle(tester);
      await tester.pumpAndSettle();
      // Фон страницы — из светлой палитры.
      final page = find.byWidgetPredicate(
        (w) =>
            w is Material &&
            (w.color == light.bg || w.color == dark.bg) &&
            w.child is! Scaffold,
      );
      final visible = page.hitTestable();
      expect(visible, findsWidgets, reason: tab);
      for (final m in tester.widgetList<Material>(visible)) {
        expect(m.color, light.bg, reason: '$tab: page background');
      }
      // Ни одного текста цветом тёмной палитры.
      final colors = textColors(tester, find.byType(Navigator).first);
      expect(
        colors.where(darkText.contains),
        isEmpty,
        reason: '$tab: text from the dark palette',
      );
    }

    // Подписи под постерами — ≥ 4,5:1 к светлому фону.
    await tester.tap(find.text('Каталог').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    final captions = <Color>[];
    for (final card in find.byType(PosterCard).evaluate().take(3)) {
      final colors = textColors(tester, find.byWidget(card.widget));
      captions.addAll(colors.where((c) => c == light.fg || c == light.fg2));
    }
    expect(captions, isNotEmpty);
    for (final c in captions) {
      expect(contrast(c, light.bg), greaterThanOrEqualTo(4.5));
    }
    await h.dispose(tester);
  });
}
