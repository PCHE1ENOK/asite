import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/data/notes/notes_repository.dart';
import 'package:anime_viewer/ui/theme/app_theme.dart';
import 'package:anime_viewer/ui/title/note_editor.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures.dart';
import 'ui_harness.dart';

/// Хранилище, которое не может сохранить.
class _FailingNotes extends NotesRepository {
  _FailingNotes(super.db);

  var fail = true;

  @override
  Future<TitleNote?> save(TitleNote note) =>
      fail ? Future.error(StateError('offline')) : super.save(note);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> center(WidgetTester tester, Finder f) async {
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> openTitle(WidgetTester tester) async {
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Сохранить'),
      matching: find.byType(FilledButton),
    ),
  );

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('block, editor states, moments and saving', (tester) async {
    await tester.runAsync(
      () => h.services.library.setStatus(16498, ListStatus.dropped),
    );
    await h.pump(tester);
    await openTitle(tester);

    // Блок между шапкой и вкладками; вкладки «Заметка» больше нет.
    expect(find.text('Моя заметка'), findsOneWidget);
    expect(find.text('Записать, почему бросили'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Заметка'), findsNothing);
    // Смена вкладки не прячет блок даже на один кадр.
    await tester.tap(find.text('Описание'));
    await tester.pump();
    expect(find.text('Моя заметка'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Моя заметка')).dy,
      lessThan(tester.getTopLeft(find.byType(TabBar)).dy),
    );

    await openEditor(tester, 'Добавить заметку');
    // ПК: панель справа шириной 480.
    expect(find.text('МОЯ ЗАМЕТКА'), findsOneWidget);
    expect(tester.getSize(find.byType(NoteEditorPanel)).width, 480);
    expect(tester.getTopRight(find.byType(NoteEditorPanel)).dx, 1440);
    expect(find.text('Новая заметка'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    // Причины — чипы и текст (статус «Брошено»).
    await tester.tap(find.text('Затянуто'));
    await tester.tap(find.text('Нет времени'));
    await tester.pump();
    expect(find.text('Есть несохранённые изменения'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.enterText(field('Своими словами'), 'после 4-й серии');

    // Моменты: проверка времени и текста, Enter добавляет.
    await center(tester, find.text('Добавить'));
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(find.text('Время в формате мм:сс, меньше 24:00'), findsOneWidget);
    await tester.enterText(field('Время'), '30:00');
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(find.text('Время в формате мм:сс, меньше 24:00'), findsOneWidget);
    await tester.enterText(field('Время'), '12:34');
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(find.text('Напишите пару слов о моменте'), findsOneWidget);
    await tester.enterText(field('Что произошло'), 'Поворот');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Серия 1 · 12:34'), findsOneWidget);
    expect(find.text('Напишите пару слов о моменте'), findsNothing);
    await tester.enterText(field('Время'), '1:05');
    await tester.enterText(field('Что произошло'), 'Начало');
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    // Сортировка по серии и времени.
    expect(
      tester.getTopLeft(find.text('Начало')).dy,
      lessThan(tester.getTopLeft(find.text('Поворот')).dy),
    );

    await center(tester, find.text('Советую'));
    await tester.tap(find.text('Советую'));
    await tester.pump();
    await center(tester, find.text('Итог одной-двумя строками'));
    await tester.enterText(
      find.byKey(const ValueKey('note-summary')),
      'x' * 200,
    );
    await tester.pump();
    expect(find.text('140/140'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('note-summary')),
      'Сильный старт',
    );

    await tester.tap(find.text('Сохранить'));
    await UiHarness.settle(tester);
    expect(find.text('Сохранено · только что'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    final n = (await UiHarness.run(
      tester,
      () => h.services.notes.note(16498),
    ))!;
    expect(n.summary, 'Сильный старт');
    expect(n.verdict, NoteVerdict.recommend);
    expect(n.dropReasons, ['Затянуто', 'Нет времени']);
    expect(n.dropText, 'после 4-й серии');
    expect(n.moments.map((m) => m.text), ['Начало', 'Поворот']);

    // Без изменений закрывается сразу; блок показывает заметку.
    await tester.tap(find.byTooltip('Закрыть'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPanel), findsNothing);
    expect(find.text('Советую'), findsOneWidget);
    expect(find.text('Сильный старт'), findsOneWidget);
    expect(
      find.textContaining(
        '2 момента · причина: Затянуто, Нет времени · обновлено',
      ),
      findsOneWidget,
    );
    expect(find.text('Редактировать'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('leaving with changes asks what to do', (tester) async {
    await h.pump(tester);
    await openTitle(tester);
    expect(
      find.text('Записать, почему бросили или что понравилось'),
      findsOneWidget,
    );
    await openEditor(tester, 'Добавить заметку');
    // Причины бросания — только у брошенных.
    expect(find.text('Почему бросили'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('note-liked')), 'Музыка');
    await tester.pump();

    // Клик по затемнению = «Закрыть».
    await tester.tapAt(const Offset(100, 450));
    await tester.pumpAndSettle();
    expect(find.text('Сохранить изменения в заметке?'), findsOneWidget);
    await tester.tap(find.text('Продолжить редактирование'));
    await tester.pumpAndSettle();
    expect(find.text('Музыка'), findsOneWidget);

    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не сохранять'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPanel), findsNothing);
    expect(find.text('Изменения не сохранены'), findsOneWidget);
    expect(
      await UiHarness.run(tester, () => h.services.notes.note(16498)),
      isNull,
    );

    // Нет автосохранения: снова пусто, теперь «Сохранить» в диалоге.
    await openEditor(tester, 'Добавить заметку');
    expect(find.text('Музыка'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('note-liked')), 'Музыка');
    await tester.pump();
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сохранить'),
      ),
    );
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPanel), findsNothing);
    expect(find.text('Заметка сохранена'), findsOneWidget);
    expect(
      (await UiHarness.run(tester, () => h.services.notes.note(16498)))!.liked,
      'Музыка',
    );
    await h.dispose(tester);
  });

  testWidgets('saving an empty note deletes it', (tester) async {
    await tester.runAsync(
      () => h.services.notes.save(
        TitleNote(mediaId: 16498, updatedAt: DateTime.now(), liked: 'Музыка'),
      ),
    );
    await h.pump(tester);
    await openTitle(tester);
    await openEditor(tester, 'Редактировать');
    expect(find.textContaining('Сохранено ·'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('note-liked')), '');
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await UiHarness.settle(tester);
    expect(find.text('Пустая заметка удалена'), findsOneWidget);
    expect(find.text('Новая заметка'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Добавить заметку'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('phone: editor is a full-screen page', (tester) async {
    await h.pump(tester, size: const Size(390, 844));
    await openTitle(tester);
    await center(tester, find.text('Добавить заметку'));
    await openEditor(tester, 'Добавить заметку');
    expect(tester.getSize(find.byType(NoteEditorPanel)), const Size(390, 844));
    expect(find.byTooltip('Назад'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Назад'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPanel), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('save error keeps the edits and offers a retry', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final notes = _FailingNotes(db);
    final details = AnimeDetails.fromJson(
      (jsonDecode(fixture('details_response.json')) as Map)['data']['Media']
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(
          body: NoteEditorPanel(
            details: details,
            notes: notes,
            profileName: 'Основной',
          ),
        ),
      ),
    );
    await UiHarness.settle(tester);
    await tester.enterText(find.byKey(const ValueKey('note-liked')), 'Музыка');
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await UiHarness.settle(tester);
    expect(
      find.textContaining('Не удалось сохранить: нет связи с хранилищем'),
      findsOneWidget,
    );
    expect(find.text('Музыка'), findsOneWidget);
    notes.fail = false;
    await tester.tap(find.text('Повторить'));
    await UiHarness.settle(tester);
    expect(find.text('Сохранено · только что'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await UiHarness.run(tester, db.close);
  });
}
