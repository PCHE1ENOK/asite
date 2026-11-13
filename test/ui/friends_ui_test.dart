import 'dart:convert';

import 'package:anime_viewer/data/share/share_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;

  setUp(() {
    h = UiHarness();
    h.github
      ..users['yuki'] = null
      ..users['empty'] = null
      ..userGists['yuki'] = {
        ShareCodec.fileName: jsonEncode({
          'version': 1,
          'owner': 'Юки',
          'titles': [
            {
              'id': 1,
              'title': {'ru': 'Фрирен'},
              'status': 'CURRENT',
              'progress': 5,
              'episodes': 28,
              'favorite': true,
              'note': {'verdict': 'recommend', 'summary': 'Тёплая и грустная'},
            },
            {
              'id': 2,
              'title': {'en': 'Attack on Titan'},
              'status': 'COMPLETED',
            },
          ],
        }),
      };
  });

  /// [signedIn] — профиль вошёл в GitHub (токен для поиска друзей).
  Future<void> openFriends(WidgetTester tester, {bool signedIn = false}) async {
    if (signedIn) {
      h.friendsToken = 'tok';
      h.tokenStore(1).token = 'tok';
    }
    await h.pump(tester);
    if (signedIn) await UiHarness.run(tester, h.services.sync.start);
    await tester.tap(find.text('Друзья').first);
    await UiHarness.settle(tester);
  }

  testWidgets('tab «Друзья» sits between «Списки» and «Поиск»', (tester) async {
    await h.pump(tester);
    final y = {
      for (final l in ['Списки', 'Друзья', 'Поиск'])
        l: tester.getCenter(find.text(l).first).dy,
    };
    expect(y['Списки']! < y['Друзья']!, isTrue);
    expect(y['Друзья']! < y['Поиск']!, isTrue);
    await h.dispose(tester);
  });

  testWidgets('without sign-in search is unavailable', (tester) async {
    await openFriends(tester);
    expect(find.text('Поиск друзей — после входа'), findsOneWidget);
    expect(find.text('Найти друга по нику GitHub'), findsNothing);
    expect(find.text('Пока нет друзей'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('search, not found, add, open catalog with tabs and notes', (
    tester,
  ) async {
    await openFriends(tester, signedIn: true);

    await tester.enterText(find.byType(TextField), 'empty');
    await tester.tap(find.text('Найти'));
    await UiHarness.settle(tester);
    expect(
      find.text('У этого пользователя нет публичного каталога'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'yuki');
    await tester.tap(find.text('Найти'));
    await UiHarness.settle(tester);
    expect(find.text('2 тайтла'), findsOneWidget);
    await tester.tap(find.text('Добавить в друзья'));
    await UiHarness.settle(tester);
    expect(find.text('Уже в друзьях'), findsOneWidget);
    expect(find.text('МОИ ДРУЗЬЯ'), findsOneWidget);

    await tester.tap(find.textContaining('в друзьях с'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Смотрю · 1'), findsOneWidget);
    expect(find.text('Просмотрено · 1'), findsOneWidget);
    expect(find.text('Понравилось · 1'), findsOneWidget);
    expect(find.text('Заметки · 1'), findsOneWidget);
    expect(find.text('Фрирен'), findsOneWidget);

    await tester.ensureVisible(find.text('Заметки · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заметки · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Тёплая и грустная'), findsOneWidget);
    expect(find.text('Советую'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('rate limit message, no crash', (tester) async {
    await openFriends(tester, signedIn: true);
    h.github.rateLimited = true;
    await tester.enterText(find.byType(TextField), 'yuki');
    await tester.tap(find.text('Найти'));
    await UiHarness.settle(tester);
    expect(
      find.text(
        'GitHub временно ограничил число запросов. Попробуйте через час',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });
}
