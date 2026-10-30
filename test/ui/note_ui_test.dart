import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  /// Прокручивает элемент к центру экрана, чтобы нажатие попало в него.
  Future<void> center(WidgetTester tester, Finder f) async {
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> openNoteTab(WidgetTester tester) async {
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Заметка'));
    await tester.tap(find.text('Заметка'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('write, save and read a note; summary shows in lists', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.services.library.setStatus(16498, ListStatus.dropped),
    );
    await h.pump(tester);
    await openNoteTab(tester);
    expect(
      find.textContaining('Личная заметка — видна только в профиле'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).at(0), 'Сильный старт');
    await tester.tap(find.text('Советую'));
    await tester.pump();
    // Причина «брошено» видна, потому что статус «Брошено».
    await center(tester, find.text('Затянуто'));
    await tester.tap(find.text('Затянуто'));
    await tester.pump();

    await center(tester, find.text('Добавить момент'));
    await tester.tap(find.text('Добавить момент'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Серия'), '3');
    await tester.enterText(
      find.widgetWithText(TextField, 'Таймкод (необязательно)'),
      '12:34',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Что запомнилось'),
      'Поворот',
    );
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Серия 3 · 12:34'), findsOneWidget);

    await center(tester, find.text('Сохранить заметку'));
    await tester.tap(find.text('Сохранить заметку'));
    await UiHarness.settle(tester);
    expect(find.text('Заметка сохранена'), findsOneWidget);

    final n = (await UiHarness.run(
      tester,
      () => h.services.notes.note(16498),
    ))!;
    expect(n.summary, 'Сильный старт');
    expect(n.verdict, NoteVerdict.recommend);
    expect(n.dropReason, 'Затянуто');
    expect(n.moments.single.timecode, const Duration(minutes: 12, seconds: 34));

    // Краткий итог в «Моих списках» (вид «список»).
    await tester.tap(find.text('Списки').first);
    await UiHarness.settle(tester);
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Брошено')),
    );
    await UiHarness.settle(tester);
    await tester.tap(find.byTooltip('Список'));
    await UiHarness.settle(tester);
    expect(find.text('Сильный старт'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('unsaved changes are kept when switching tabs', (tester) async {
    await h.pump(tester);
    await openNoteTab(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Черновик');
    await tester.tap(find.text('Серии'));
    await UiHarness.settle(tester);
    await tester.tap(find.text('Заметка'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('moment dialog validates input', (tester) async {
    await h.pump(tester);
    await openNoteTab(tester);
    await center(tester, find.text('Добавить момент'));
    await tester.tap(find.text('Добавить момент'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Серия'), '99');
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(find.text('Номер серии от 1 до 25'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Серия'), '2');
    await tester.enterText(
      find.widgetWithText(TextField, 'Таймкод (необязательно)'),
      '1:99',
    );
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(find.text('Таймкод в формате 12:34 или 1:02:03'), findsOneWidget);
    await h.dispose(tester);
  });
}
