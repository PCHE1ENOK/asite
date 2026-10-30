import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/sources/youtube_comments.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> thread(
  String id,
  String text, {
  int likes = 0,
  int replies = 0,
}) => {
  'id': id,
  'snippet': {
    'totalReplyCount': replies,
    'topLevelComment': {
      'id': id,
      'snippet': {
        'authorDisplayName': 'Автор $id',
        'authorProfileImageUrl': 'https://yt3.ggpht.com/$id.jpg',
        'textDisplay': text,
        'textOriginal': text,
        'likeCount': likes,
        'publishedAt': '2026-10-01T12:00:00Z',
      },
    },
  },
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late List<Uri> requests;
  late http.Response Function(Uri) handler;
  var now = DateTime.utc(2026, 10, 30, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    now = DateTime.utc(2026, 10, 30, 12);
    handler = (uri) => http.Response.bytes(
      utf8.encode(
        jsonEncode(
          uri.queryParameters['pageToken'] == null
              ? {
                  'nextPageToken': 'P2',
                  'items': [
                    thread('a', 'Первый', likes: 1200, replies: 3),
                    thread('b', 'Второй'),
                  ],
                }
              : {
                  'items': [thread('c', 'Третий')],
                },
        ),
      ),
      200,
    );
  });
  tearDown(() => db.close());

  YouTubeCommentsClient client({String key = 'k'}) => YouTubeCommentsClient(
    apiKey: key,
    db: db,
    clock: () => now,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      return handler(r.url);
    }),
  );

  test('parses a page and follows nextPageToken', () async {
    final c = client();
    final first = await c.fetch('vid') as CommentsLoaded;
    expect(first.page.comments.map((x) => x.text), ['Первый', 'Второй']);
    expect(first.page.comments.first.likes, 1200);
    expect(first.page.comments.first.replies, 3);
    expect(first.page.comments.first.author, 'Автор a');
    expect(
      first.page.comments.first.authorAvatar,
      'https://yt3.ggpht.com/a.jpg',
    );
    expect(first.page.nextPageToken, 'P2');

    final second = await c.fetch('vid', pageToken: 'P2') as CommentsLoaded;
    expect(second.page.comments.single.text, 'Третий');
    expect(second.page.hasMore, isFalse);

    final q = requests.first.queryParameters;
    expect(requests.first.path, '/youtube/v3/commentThreads');
    expect(q['videoId'], 'vid');
    expect(q['part'], 'snippet');
    expect(q['order'], 'relevance');
    expect(q['maxResults'], '20');
    expect(q['textFormat'], 'plainText');
    expect(requests[1].queryParameters['pageToken'], 'P2');
  });

  test('order by time is passed to the API', () async {
    await client().fetch('vid', order: CommentOrder.time);
    expect(requests.single.queryParameters['order'], 'time');
  });

  test('comments disabled (403 commentsDisabled)', () async {
    handler = (_) => http.Response(
      jsonEncode({
        'error': {
          'code': 403,
          'errors': [
            {'reason': 'commentsDisabled', 'domain': 'youtube.commentThread'},
          ],
        },
      }),
      403,
    );
    expect(await client().fetch('vid'), isA<CommentsDisabled>());
  });

  test('other errors and no key fail without throwing', () async {
    handler = (_) => http.Response(
      '{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}',
      403,
    );
    expect(await client().fetch('vid'), isA<CommentsFailed>());
    expect(await client(key: '').fetch('vid'), isA<CommentsFailed>());
    handler = (_) => throw http.ClientException('offline');
    expect(await client().fetch('other'), isA<CommentsFailed>());
  });

  test('empty list', () async {
    handler = (_) => http.Response('{"items":[]}', 200);
    final r = await client().fetch('vid') as CommentsLoaded;
    expect(r.page.comments, isEmpty);
    expect(r.page.hasMore, isFalse);
  });

  test('cached for one hour', () async {
    final c = client();
    await c.fetch('vid');
    now = now.add(const Duration(minutes: 59));
    await c.fetch('vid');
    expect(requests, hasLength(1));
    now = now.add(const Duration(minutes: 2));
    await c.fetch('vid');
    expect(requests, hasLength(2));
  });

  test('text stays plain: markup is kept as characters', () {
    final r = YouTubeCommentsClient.parse({
      'items': [thread('x', '<b>жирный</b> <script>alert(1)</script> &amp;')],
    });
    expect(
      r.page.comments.single.text,
      '<b>жирный</b> <script>alert(1)</script> &amp;',
    );
  });
}
