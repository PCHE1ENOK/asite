import 'dart:convert';

import 'package:anime_viewer/ui/player/youtube_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ui_harness.dart';

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

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

  testWidgets('section without results shows an empty state', (tester) async {
    await openTab(tester);
    expect(find.text('Эдиты'), findsOneWidget);
    expect(find.text('Обзоры'), findsOneWidget);
    expect(find.text('Смешные моменты'), findsOneWidget);
    expect(find.text('В этом разделе пока ничего нет'), findsOneWidget);
    final q = h.communityRequests.single.queryParameters;
    expect(q['safeSearch'], 'strict');
    expect(q['q'], 'Attack on Titan AMV');

    await tester.tap(find.text('Обзоры'));
    await UiHarness.settle(tester);
    expect(
      h.communityRequests.last.queryParameters['q'],
      'Attack on Titan review',
    );
    expect(find.text('В этом разделе пока ничего нет'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('quota exhausted: message, no crash', (tester) async {
    h.communityHandler = (_) =>
        http.Response('{"error":{"errors":[{"reason":"quotaExceeded"}]}}', 403);
    await openTab(tester);
    expect(
      find.text('Лимит поиска исчерпан, попробуйте завтра'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets('tap opens the embedded player without comments', (tester) async {
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
                'snippet': {'title': 'Лучший AMV', 'channelTitle': 'Фанат'},
                'contentDetails': {'contentRating': {}},
                'status': {'embeddable': true, 'privacyStatus': 'public'},
              },
            ],
          });
    await openTab(tester);
    expect(find.text('Лучший AMV'), findsOneWidget);
    expect(find.text('Фанат'), findsOneWidget);
    await tester.tap(find.text('Лучший AMV'));
    await UiHarness.settle(tester);
    expect(find.text('iframe v1'), findsOneWidget);
    expect(find.text('Открыть на YouTube'), findsWidgets);
    expect(find.text('Комментарии'), findsNothing);
    await h.dispose(tester);
  });
}
