import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:anime_viewer/ui/widgets/verdict_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  testWidgets('verdict badge, summary and verdict filter in «Мои списки»', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final id in [1000, 1001, 1002]) {
        await h.services.library.setStatus(id, ListStatus.completed);
      }
      await h.services.notes.save(
        TitleNote(
          mediaId: 1000,
          updatedAt: DateTime.now(),
          summary: 'Лучшее за год',
          verdict: NoteVerdict.recommend,
        ),
      );
      await h.services.notes.save(
        TitleNote(
          mediaId: 1001,
          updatedAt: DateTime.now(),
          verdict: NoteVerdict.notRecommend,
          liked: 'музыка',
        ),
      );
    });
    // Карточки в кэше из каталога.
    await h.pump(tester);
    await tester.tap(find.text('Списки').first);
    await UiHarness.settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Просмотрено'),
      ),
    );
    await UiHarness.settle(tester);

    expect(find.byType(PosterCard), findsNWidgets(3));
    expect(find.byType(VerdictBadge), findsNWidgets(2));
    expect(find.text('Лучшее за год'), findsOneWidget);

    await tester.tap(find.text('Советую'));
    await UiHarness.settle(tester);
    expect(find.byType(PosterCard), findsOneWidget);

    await tester.tap(find.text('С заметкой'));
    await UiHarness.settle(tester);
    expect(find.byType(PosterCard), findsNWidgets(2));

    await tester.tap(find.text('Стоит пересмотреть'));
    await UiHarness.settle(tester);
    expect(find.text('Нет тайтлов с таким вердиктом'), findsOneWidget);
    await tester.tap(find.text('Показать все'));
    await UiHarness.settle(tester);
    expect(find.byType(PosterCard), findsNWidgets(3));
    await h.dispose(tester);
  });
}
