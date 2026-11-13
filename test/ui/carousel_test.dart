import 'dart:convert';

import 'package:anime_viewer/ui/widgets/badges.dart';
import 'package:anime_viewer/ui/widgets/poster_carousel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import 'ui_harness.dart';

void main() {
  late UiHarness h;

  /// Тайтлы фикстуры со статусом из запроса: онгоинги для текущего
  /// сезона, анонсы для следующего, вышедшие для прошедших.
  String page(String? status) {
    final page = jsonDecode(fixture('catalog_page_30.json')) as Map;
    for (final m in page['data']['Page']['media'] as List) {
      (m as Map)['status'] = status ?? 'FINISHED';
    }
    return jsonEncode(page);
  }

  setUp(() {
    h = UiHarness(seasons: true)
      ..seasonHandler = (vars) => jsonResponse(page(vars['status'] as String?));
  });

  Finder first() => find.byType(PosterCarousel).first;

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: first(), matching: find.byType(Scrollable)),
      )
      .position
      .pixels;

  testWidgets('four seasons above the catalog, current first; season vars', (
    tester,
  ) async {
    await h.pump(tester);
    expect(find.text('АНИМЕ ОСЕННЕГО СЕЗОНА'), findsOneWidget);
    expect(find.text('Осень 2026 · сейчас идёт'), findsOneWidget);
    expect(h.seasonRequests.first['season'], 'FALL');
    expect(h.seasonRequests.first['seasonYear'], 2026);
    expect(h.seasonRequests.first['status'], 'RELEASING');
    expect(
      h.seasonRequests.map(
        (v) => '${v['season']} ${v['seasonYear']} ${v['status']}',
      ),
      [
        'FALL 2026 RELEASING',
        'SUMMER 2026 null',
        'SPRING 2026 null',
        'WINTER 2027 NOT_YET_RELEASED',
      ],
    );
    await h.dispose(tester);
  });

  testWidgets('announces: last, no score badge, «анонс» caption', (
    tester,
  ) async {
    await h.pump(tester);
    final announces = find.byType(PosterCarousel).last;
    await tester.scrollUntilVisible(
      announces,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('АНОНСЫ · ЗИМА 2027'), findsOneWidget);
    expect(find.text('Ещё не вышли'), findsOneWidget);
    expect(
      find.descendant(of: announces, matching: find.textContaining('· анонс')),
      findsWidgets,
    );
    expect(
      find.descendant(of: announces, matching: find.byType(AnimeScoreBadge)),
      findsNothing,
    );
    await h.dispose(tester);
  });

  testWidgets('steps one card every 5 s', (tester) async {
    await h.pump(tester);
    expect(offset(tester), 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(tester), 180, reason: 'карточка 160 + промежуток 20');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(tester), 360);
    await h.dispose(tester);
  });

  testWidgets('pauses on mouse hover', (tester) async {
    await h.pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(
        find.descendant(of: first(), matching: find.byType(Scrollable)),
      ),
    );
    await tester.pump();
    expect(find.text('Пауза'), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    expect(offset(tester), 0);
    // Указатель ушёл — снова листает.
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(tester), 180);
    await h.dispose(tester);
  });

  testWidgets('pauses on touch and 5 s after it', (tester) async {
    await h.pump(tester);
    final strip = tester.getCenter(
      find.descendant(of: first(), matching: find.byType(Scrollable)),
    );
    final finger = await tester.startGesture(strip);
    await tester.pump(const Duration(seconds: 6));
    expect(offset(tester), 0, reason: 'палец на ленте');
    await finger.up();
    await tester.pump(const Duration(seconds: 3));
    expect(offset(tester), 0, reason: 'ещё 5 с после касания');
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(tester), greaterThan(0));
    await h.dispose(tester);
  });

  testWidgets('reduced motion: no autoscroll, no indicator', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await h.pump(tester);
    await tester.pump(const Duration(seconds: 11));
    expect(offset(tester), 0);
    expect(find.text('Пауза'), findsNothing);
    expect(find.bySemanticsLabel('Остановить автопрокрутку'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('setting off: no autoscroll', (tester) async {
    await tester.runAsync(() => h.settings.setAutoScroll(false));
    await h.pump(tester);
    await tester.pump(const Duration(seconds: 11));
    expect(offset(tester), 0);
    await h.dispose(tester);
  });

  testWidgets('indicator stops autoscroll with a toast; arrows move', (
    tester,
  ) async {
    await h.pump(tester);
    final indicator = find.descendant(
      of: first(),
      matching: find.bySemanticsLabel('Остановить автопрокрутку'),
    );
    await tester.tap(indicator);
    await tester.pump();
    expect(find.text(PosterCarousel.stoppedToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(offset(tester), 0);

    // Стрелки остаются: «‹» скрыта в начале, «›» сдвигает на карточку.
    expect(
      find.descendant(of: first(), matching: find.byTooltip('Назад')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: first(), matching: find.byTooltip('Вперёд')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(tester), 180);
    expect(
      find.descendant(of: first(), matching: find.byTooltip('Назад')),
      findsOneWidget,
    );
    await h.dispose(tester);
  });
}
