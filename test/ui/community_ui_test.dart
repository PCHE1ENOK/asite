import 'dart:convert';

import 'package:anime_viewer/ui/player/youtube_player_screen.dart';
import 'package:anime_viewer/ui/title/community_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ui_harness.dart';

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  late UiHarness h;
  setUp(() {
    h = UiHarness();
    CommunityTab.resetSection();
  });

  /// «Сообщество» — вкладка карточки тайтла (общая страница убрана).
  Future<void> openTab(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сообщество'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сообщество'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('tab is in the title card, not in the navigation', (
    tester,
  ) async {
    await h.pump(tester);
    expect(find.text('Сообщество'), findsNothing);
    // Телефон: нижняя панель — тоже без «Сообщества».
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Сообщество'), findsNothing);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    // Последняя в ряду вкладок карточки.
    await tester.dragUntilVisible(
      find.text('Похожие'),
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сообщество'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Сообщество')).dx,
      greaterThan(tester.getCenter(find.text('Похожие')).dx),
    );
    await h.dispose(tester);
  });

  testWidgets('retell first; empty section; Russian queries only', (
    tester,
  ) async {
    await openTab(tester);
    final labels = ['Пересказ аниме', 'Эдиты', 'Обзоры', 'Смешные моменты'];
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    // «Пересказ аниме» — первый и выбран по умолчанию.
    expect(
      tester.getTopLeft(find.text('Пересказ аниме')).dx,
      lessThan(tester.getTopLeft(find.text('Эдиты')).dx),
    );
    expect(find.text('Роликов не нашлось'), findsOneWidget);
    expect(
      find.text(
        'По «Attack on Titan» в разделе «Пересказ аниме» пока ничего. '
        'Загляните в другой раздел.',
      ),
      findsOneWidget,
    );
    // Русского названия в тесте нет — поиск по ромадзи.
    expect(h.communityRequests.map((u) => u.queryParameters['q']), [
      'Переозвучка Shingeki no Kyojin',
      'Shingeki no Kyojin за 15 минут',
    ]);
    expect(h.communityRequests.first.queryParameters['safeSearch'], 'strict');
    expect(find.text(CommunityTab.note), findsOneWidget);

    await tester.tap(find.text('Обзоры'));
    await UiHarness.settle(tester);
    expect(
      h.communityRequests.last.queryParameters['q'],
      'Shingeki no Kyojin обзор',
    );
    expect(
      h.communityRequests.map((u) => u.queryParameters['relevanceLanguage']),
      everyElement('ru'),
    );
    await h.dispose(tester);
  });

  testWidgets('quota exhausted: message with reset time, no crash', (
    tester,
  ) async {
    h.communityHandler = (_) =>
        http.Response('{"error":{"errors":[{"reason":"quotaExceeded"}]}}', 403);
    await openTab(tester);
    expect(
      find.text('Лимит поиска исчерпан, попробуйте завтра'),
      findsOneWidget,
    );
    expect(find.textContaining('Поиск снова заработает в '), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets('card: duration, open button; tap opens player, no comments', (
    tester,
  ) async {
    YouTubePlayerScreen.debugEmbedBuilder = (id, onEvent) => Text('iframe $id');
    addTearDown(() => YouTubePlayerScreen.debugEmbedBuilder = null);
    h.communityHandler = (uri) => uri.path.endsWith('/search')
        ? json({
            'items': [
              {
                'id': {'videoId': 'v1'},
              },
            ],
          })
        : json({
            'items': [
              {
                'id': 'v1',
                'snippet': {
                  'title': 'Пересказ за 15 минут',
                  'channelTitle': 'Фанат',
                },
                'contentDetails': {'duration': 'PT14M5S', 'contentRating': {}},
                'status': {'embeddable': true, 'privacyStatus': 'public'},
              },
            ],
          });
    await openTab(tester);
    // Найден обоими запросами раздела — показан один раз.
    expect(find.text('Пересказ за 15 минут'), findsOneWidget);
    expect(find.text('Фанат'), findsOneWidget);
    expect(find.text('14:05'), findsOneWidget);
    expect(find.byTooltip('Открыть на YouTube'), findsOneWidget);
    expect(find.text('RU'), findsNothing, reason: 'бейджа языка нет');

    await tester.tap(find.text('Пересказ за 15 минут'));
    await UiHarness.settle(tester);
    expect(find.text('iframe v1'), findsOneWidget);
    expect(find.text('Фанат · Пересказ аниме'), findsOneWidget);
    expect(
      find.text('Ролик пользователя · не от правообладателя'),
      findsOneWidget,
    );
    expect(find.text('Комментарии'), findsNothing);
    await h.dispose(tester);
  });
}
