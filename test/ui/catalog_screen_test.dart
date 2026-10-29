import 'package:anime_viewer/ui/widgets/badges.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() => h = UiHarness());
  tearDown(() {});

  testWidgets('shows posters with score and 18+ badge', (tester) async {
    await h.pump(tester);

    expect(find.text('Каталог'), findsWidgets);
    expect(find.byType(PosterCard), findsWidgets);
    expect(find.text("Frieren: Beyond Journey's End"), findsOneWidget);
    expect(find.text('TV · 2023 · 28 эп.'), findsOneWidget);
    expect(find.text('90'), findsWidgets);
    expect(h.catalogRequests.first, {
      'sort': ['POPULARITY_DESC'],
      'page': 1,
      'perPage': 30,
    });
    await h.dispose(tester);
  });

  testWidgets('format chip filters and reset clears', (tester) async {
    await h.pump(tester);

    await tester.tap(find.text('Фильм'));
    await UiHarness.settle(tester);
    expect(h.catalogRequests.last['formats'], ['MOVIE']);

    final before = h.catalogRequests.length;
    await tester.tap(find.text('Сбросить'));
    await UiHarness.settle(tester);
    // Первая страница без фильтров уже в кэше — в сеть не идём.
    expect(h.catalogRequests.length, before);
    expect(find.text('Сбросить'), findsNothing);
    expect(find.text('Attack on Titan'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('sort menu changes MediaSort', (tester) async {
    await h.pump(tester);

    await tester.tap(find.text('Популярность'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рейтинг AniList').last);
    await UiHarness.settle(tester);

    expect(h.catalogRequests.last['sort'], ['SCORE_DESC']);
    await h.dispose(tester);
  });

  testWidgets('18+ chip is shared with settings and filters requests', (
    tester,
  ) async {
    await h.pump(tester);
    await tester.scrollUntilVisible(
      find.text('Redo of Healer'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(AdultBadge), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Показывать 18+'));
    await UiHarness.settle(tester);

    expect(h.settings.showAdult, isFalse);
    expect(h.catalogRequests.last['isAdult'], false);
    expect(find.text('Сбросить'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('error state with retry', (tester) async {
    h.offline = true;
    await h.pump(tester);

    expect(
      find.text('Не удалось загрузить каталог. Проверьте подключение'),
      findsOneWidget,
    );

    h.offline = false;
    await tester.tap(find.text('Повторить'));
    await UiHarness.settle(tester);
    expect(find.byType(PosterCard), findsWidgets);
    await h.dispose(tester);
  });

  testWidgets('opening a poster shows the title card inside the tab', (
    tester,
  ) async {
    await h.pump(tester);

    await tester.tap(find.text('Attack on Titan'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Рейтинг AniList'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('за сезон'), findsOneWidget);
    // Навигация остаётся на экране.
    expect(find.text('Поиск'), findsWidgets);
    await h.dispose(tester);
  });

  testWidgets('compact width uses bottom navigation', (tester) async {
    await h.pump(tester, size: const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    await h.dispose(tester);
  });
}
