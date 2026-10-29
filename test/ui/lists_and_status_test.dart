import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:anime_viewer/ui/widgets/status_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<LibraryEntry?> entry(WidgetTester tester, int id) =>
      UiHarness.run(tester, () => h.services.library.entry(id));

  Finder tab(String label) =>
      find.descendant(of: find.byType(TabBar), matching: find.text(label));

  Future<void> openAot(WidgetTester tester) async {
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('status button adds and changes status', (tester) async {
    await h.pump(tester);
    await openAot(tester);

    await tester.tap(find.text('Добавить в список'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В планах').last);
    await UiHarness.settle(tester);

    expect((await entry(tester, 16498))?.status, ListStatus.planning);
    expect(find.text('В планах'), findsOneWidget);

    await tester.tap(find.text('В планах'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить из списка'));
    await UiHarness.settle(tester);
    expect(await entry(tester, 16498), isNull);
    expect(find.text('Добавить в список'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('marking an episode sets CURRENT, shows undo', (tester) async {
    await h.pump(tester);
    await openAot(tester);

    await tester.tap(find.byTooltip('Отметить просмотренной').first);
    await UiHarness.settle(tester);

    expect(
      find.text('Серия 1 отмечена просмотренной · статус «Смотрю»'),
      findsOneWidget,
    );
    final e = await entry(tester, 16498);
    expect(e?.status, ListStatus.current);
    expect(e?.progress, 1);
    expect(find.text('Смотреть серию 2'), findsOneWidget);
    expect(find.byTooltip('Снять отметку'), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await UiHarness.settle(tester);
    expect(await entry(tester, 16498), isNull);
    expect(find.text('Начать просмотр'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('poster shows status dot; right click changes status', (
    tester,
  ) async {
    await h.pump(tester);
    expect(find.byType(ListStatusDot), findsNothing);

    await tester.tap(
      find.text('Attack on Titan'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Просмотрено').last);
    await UiHarness.settle(tester);

    expect((await entry(tester, 1001))?.status, ListStatus.completed);
    expect(find.byType(ListStatusDot), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('hide-from-my-lists sends id_not_in', (tester) async {
    await tester.runAsync(
      () => h.services.library.setStatus(1001, ListStatus.planning),
    );
    await h.pump(tester);
    expect(find.byType(ListStatusDot), findsOneWidget);

    await tester.tap(find.text('Скрыть из моих списков'));
    await UiHarness.settle(tester);
    expect(h.catalogRequests.last['excludeIds'], [1001]);
    await h.dispose(tester);
  });

  testWidgets('lists screen: summary, tabs with counts, grid and list', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await h.services.library.setStatus(1000, ListStatus.current);
      await h.services.library.setProgress(1000, 5);
      await h.services.library.setStatus(1001, ListStatus.planning);
      await h.services.library.setStatus(1002, ListStatus.completed);
    });
    await h.pump(tester);
    await tester.tap(find.text('Списки'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Мои списки'), findsOneWidget);
    expect(find.text('3 тайтла в списках'), findsOneWidget);
    expect(find.textContaining('Только на этом устройстве'), findsOneWidget);
    // Вкладка «Смотрю»: постер с прогрессом.
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.text('TV · 2023 · 5 / 28 эп.'), findsOneWidget);
    expect(
      h.fake.requests.where((r) => (r['query'] as String).contains('ByIds')),
      isEmpty,
      reason: 'summaries are cached from the catalog',
    );

    await tester.tap(tab('Брошено'));
    await tester.pumpAndSettle();
    expect(
      find.text('Здесь появятся тайтлы, которые вы отметили «Брошено»'),
      findsOneWidget,
    );

    await tester.tap(tab('В планах'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Список'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 25'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('lists fetch missing summaries by id', (tester) async {
    await tester.runAsync(
      () => h.services.library.setStatus(1005, ListStatus.planning),
    );
    await h.pump(tester);
    await tester.tap(find.text('Списки'));
    await UiHarness.settle(tester);
    await tester.tap(tab('В планах'));
    await UiHarness.settle(tester);
    expect(find.text('DAN DA DAN'), findsWidgets);
    await h.dispose(tester);
  });
}
