import 'package:anime_viewer/ui/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openSearch(WidgetTester tester) async {
    await h.pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await UiHarness.settle(tester);
  }

  int searchRequests() =>
      h.catalogRequests.where((v) => v.containsKey('search')).length;

  testWidgets('Ctrl+K opens search; trending chips shown', (tester) async {
    await openSearch(tester);
    expect(
      find.text('Название на русском, английском или ромадзи'),
      findsOneWidget,
    );
    expect(find.text('ПОПУЛЯРНОЕ СЕЙЧАС'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('queries after debounce from 2 characters', (tester) async {
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'f');
    await tester.pump(const Duration(milliseconds: 400));
    await UiHarness.settle(tester);
    expect(searchRequests(), 0);

    await tester.enterText(find.byType(TextField), 'fr');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'fri');
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);

    expect(searchRequests(), 1);
    expect(h.catalogRequests.last['search'], 'fri');
    expect(h.catalogRequests.last['sort'], ['SEARCH_MATCH']);
    expect(find.textContaining('Результаты'), findsOneWidget);
    expect(find.byType(PosterCard), findsWidgets);
    // Поле не теряет фокус, когда появляются результаты.
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasFocus, isTrue);
    await h.dispose(tester);
  });

  testWidgets('Enter opens the first suggestion and saves the query', (
    tester,
  ) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'Frieren');
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await UiHarness.settle(tester);

    await tester.pumpAndSettle();

    expect(find.text('Рейтинг AniList'), findsOneWidget);
    expect(h.settings.recentSearches, ['Frieren']);
    await h.dispose(tester);
  });

  testWidgets('empty result message', (tester) async {
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), UiHarness.nothing);
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);

    expect(
      find.text('Ничего не нашлось по «${UiHarness.nothing}»'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });

  testWidgets('network error message', (tester) async {
    await openSearch(tester);
    h.offline = true;
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);

    expect(
      find.text('Поиск недоступен без сети. Проверьте подключение'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });
}
