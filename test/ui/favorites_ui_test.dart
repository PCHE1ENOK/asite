import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/ui/widgets/favorite_button.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Finder heartOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(PosterCard)),
    matching: find.byType(FavoriteButton),
  );

  testWidgets('phone: heart on the poster, toast with undo', (tester) async {
    await h.pump(tester, size: const Size(390, 844));
    // На телефоне неотмеченное сердце видно всегда.
    expect(heartOf('Attack on Titan'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: heartOf('Attack on Titan'),
        matching: find.byTooltip('В «Понравилось»'),
      ),
    );
    await UiHarness.settle(tester);
    expect(find.text('«Attack on Titan» в «Понравилось»'), findsOneWidget);
    expect(h.services.favorites.ids.value, {1001});
    expect(
      find.descendant(
        of: heartOf('Attack on Titan'),
        matching: find.byTooltip('Убрать из «Понравилось»'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Отменить'));
    await UiHarness.settle(tester);
    expect(h.services.favorites.ids.value, isEmpty);
    await h.dispose(tester);
  });

  testWidgets('desktop: unmarked heart only on hover; marked always', (
    tester,
  ) async {
    await h.pump(tester);
    expect(find.byTooltip('В «Понравилось»'), findsNothing);
    await UiHarness.run(tester, () => h.services.favorites.set(1001, true));
    await UiHarness.settle(tester);
    expect(find.byTooltip('Убрать из «Понравилось»'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('tab «Понравилось»: only marked titles, independent of status', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await h.services.library.setStatus(1001, ListStatus.current);
      await h.services.library.setStatus(1002, ListStatus.planning);
      await h.services.favorites.set(1001, true);
      await h.services.favorites.set(1003, true); // не в списках
    });
    await h.pump(tester);
    await tester.tap(find.text('Списки').first);
    await UiHarness.settle(tester);
    await tester.tap(find.text('Понравилось'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    final titles = find
        .byType(PosterCard)
        .evaluate()
        .map((e) => (e.widget as PosterCard).anime.id)
        .toSet();
    expect(titles, {1001, 1003});
    // «Смотрю» осталось: тайтл и там, и в «Понравилось».
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Смотрю')),
    );
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(
      find
          .byType(PosterCard)
          .evaluate()
          .map((e) => (e.widget as PosterCard).anime.id),
      [1001],
    );
    await h.dispose(tester);
  });

  testWidgets('empty tab', (tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Списки').first);
    await UiHarness.settle(tester);
    await tester.tap(find.text('Понравилось'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Отметьте тайтлы сердцем'), findsOneWidget);
    expect(find.text('Открыть каталог'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('title card heart toggles', (tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('В «Понравилось»'));
    await UiHarness.settle(tester);
    expect(h.services.favorites.ids.value, contains(16498));
    expect(find.byTooltip('Убрать из «Понравилось»'), findsWidgets);
    await h.dispose(tester);
  });
}
