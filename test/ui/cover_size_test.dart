import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('catalog asks for covers that fit the poster, only visible', (
    tester,
  ) async {
    final urls = <String>[];
    final h = UiHarness(
      images: (u) {
        urls.add(u);
        return fakeImage(u);
      },
    );
    await h.pump(tester);
    expect(find.byType(PosterCard), findsWidgets);
    // Постер 148–220 px при DPR 1 — large (≈ 230 px), не extraLarge.
    expect(urls, isNotEmpty);
    expect(urls.every((u) => u.endsWith('-m.jpg')), isTrue, reason: '$urls');
    // Грузятся только видимые карточки, не все 30.
    expect(urls.toSet().length, lessThan(30));
    await h.dispose(tester);
  });

  testWidgets('phone list rows use medium', (tester) async {
    final urls = <String>[];
    final h = UiHarness(
      images: (u) {
        urls.add(u);
        return fakeImage(u);
      },
    );
    await h.pump(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('Поиск').first);
    await UiHarness.settle(tester);
    await tester.enterText(find.byType(TextField), 'Fri');
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);
    expect(urls.any((u) => u.endsWith('-s.jpg')), isTrue, reason: '$urls');
    await h.dispose(tester);
  });
}
