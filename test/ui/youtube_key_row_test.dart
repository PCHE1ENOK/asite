import 'package:anime_viewer/data/sources/youtube_key_check.dart';
import 'package:anime_viewer/ui/settings/settings_screen.dart';
import 'package:anime_viewer/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String?>> pump(
    WidgetTester tester, {
    String current = '',
    YouTubeKeyCheck result = YouTubeKeyCheck.ok,
  }) async {
    final saved = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: YouTubeKeyRow(
              currentKey: () => current,
              save: (k) async => saved.add(k),
              check: (_) async => result,
            ),
          ),
        ),
      ),
    );
    return saved;
  }

  testWidgets('no key: «Не задан», explanation, check then save', (
    tester,
  ) async {
    final saved = await pump(tester);
    expect(find.text('Не задан'), findsOneWidget);
    expect(find.textContaining('Без ключа не работают'), findsOneWidget);
    expect(find.text('Удалить ключ'), findsNothing);
    expect(find.text('Как получить ключ'), findsOneWidget);
    expect(
      find.textContaining(
        'Ключ хранится только в этом браузере',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'AIzaNew');
    await tester.tap(find.text('Проверить и сохранить'));
    await tester.pumpAndSettle();
    expect(saved, ['AIzaNew']);
  });

  testWidgets('invalid key: error under the field, nothing saved', (
    tester,
  ) async {
    final saved = await pump(tester, result: YouTubeKeyCheck.invalid);
    await tester.enterText(find.byType(TextField), 'AIzaBad');
    await tester.tap(find.text('Проверить и сохранить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ключ не подошёл'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('key set: masked status, delete', (tester) async {
    final saved = await pump(
      tester,
      current: 'AIzaSyA1234567890abcdefghijklmnoprsXY',
    );
    expect(find.text('✓ Задан · AIza…rsXY'), findsOneWidget);
    expect(find.text('Новый ключ'), findsOneWidget);
    await tester.tap(find.text('Удалить ключ'));
    await tester.pumpAndSettle();
    expect(saved, [null]);
  });
}
