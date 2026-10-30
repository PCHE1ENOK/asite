import 'dart:convert';

import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ui_harness.dart';

const video = EmbeddedVideo(
  sourceId: 'fake',
  videoId: 'abc123XYZ_-',
  title: 'Attack on Titan Episode 1',
  channel: 'Muse Asia',
  episode: 1,
);

Map<String, dynamic> thread(String id, String text) => {
  'id': id,
  'snippet': {
    'topLevelComment': {
      'id': id,
      'snippet': {
        'authorDisplayName': 'Автор $id',
        'textOriginal': text,
        'likeCount': 5,
        'publishedAt': '2026-10-01T12:00:00Z',
      },
    },
  },
};

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openTitle(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> openComments(WidgetTester tester) async {
    await openTitle(tester);
    await tester.ensureVisible(find.text('Комментарии'));
    await tester.tap(find.text('Комментарии'));
    await UiHarness.settle(tester);
  }

  testWidgets('no official video — no comments tab', (tester) async {
    await openTitle(tester);
    expect(find.text('Комментарии'), findsNothing);
    expect(find.text('Похожие'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('comments as plain text, pagination, order switch', (
    tester,
  ) async {
    h.videoSource
      ..isConfigured = true
      ..videos = const [video];
    h.commentsHandler = (uri) => http.Response.bytes(
      utf8.encode(
        jsonEncode(
          uri.queryParameters['pageToken'] == null
              ? {
                  'nextPageToken': 'P2',
                  'items': [thread('a', '<b>не HTML</b> https://example.com')],
                }
              : {
                  'items': [thread('b', 'Вторая страница')],
                },
        ),
      ),
      200,
    );
    await openComments(tester);

    expect(find.text('<b>не HTML</b> https://example.com'), findsOneWidget);
    expect(find.textContaining('Автор a', findRichText: true), findsOneWidget);
    expect(find.text('Комментарии — с YouTube'), findsOneWidget);
    // «Открыть на YouTube» у каждого комментария.
    expect(find.text('Открыть на YouTube'), findsOneWidget);

    await tester.ensureVisible(find.text('Показать ещё'));
    await tester.tap(find.text('Показать ещё'));
    await UiHarness.settle(tester);
    expect(find.text('Вторая страница'), findsOneWidget);
    expect(find.text('Показать ещё'), findsNothing);

    await tester.ensureVisible(find.text('По времени'));
    await tester.tap(find.text('По времени'));
    await UiHarness.settle(tester);
    expect(h.commentRequests.last.queryParameters['order'], 'time');
    await h.dispose(tester);
  });

  testWidgets('disabled, empty and failed states', (tester) async {
    h.videoSource
      ..isConfigured = true
      ..videos = const [video];
    h.commentsHandler = (_) => http.Response(
      '{"error":{"code":403,"errors":[{"reason":"commentsDisabled"}]}}',
      403,
    );
    await openComments(tester);
    expect(
      find.text(
        'Комментарии отключены для этого видео. Так решил правообладатель на YouTube',
      ),
      findsOneWidget,
    );

    h.commentsHandler = (_) => http.Response('{"items":[]}', 200);
    await tester.tap(find.text('По времени'));
    await UiHarness.settle(tester);
    expect(
      find.textContaining('Комментариев пока нет. Будьте первым'),
      findsOneWidget,
    );

    h.commentsHandler = (_) => http.Response('boom', 500);
    await tester.tap(find.text('По популярности'));
    await UiHarness.settle(tester);
    expect(
      find.text(
        'Не удалось загрузить комментарии. Проверьте подключение к интернету',
      ),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsOneWidget);
    await h.dispose(tester);
  });
}
