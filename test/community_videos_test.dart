import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/sources/community_videos.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> video(
  String id, {
  String? title,
  bool embeddable = true,
  String? ytRating,
  Map<String, dynamic>? region,
  List<String> tags = const [],
}) => {
  'id': id,
  'snippet': {
    'title': title ?? 'Ролик $id',
    'channelTitle': 'Канал $id',
    'tags': tags,
    'thumbnails': {
      'medium': {'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg'},
    },
  },
  'contentDetails': {
    'contentRating': {'ytRating': ?ytRating},
    'regionRestriction': ?region,
  },
  'status': {'embeddable': embeddable, 'privacyStatus': 'public'},
};

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late List<Uri> requests;
  late List<Map<String, dynamic>> videos;
  late DateTime now;

  CommunityVideos source({String key = 'k'}) => CommunityVideos(
    apiKey: key,
    db: db,
    regionCode: 'RU',
    clock: () => now,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      if (r.url.path.endsWith('/search')) {
        return json({
          'items': [
            for (final v in videos)
              {
                'id': {'kind': 'youtube#video', 'videoId': v['id']},
              },
          ],
        });
      }
      return json({'items': videos});
    }),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    videos = [video('a'), video('b')];
    now = DateTime.utc(2026, 11, 12, 10);
  });
  tearDown(() => db.close());

  test(
    'strict safe search, embeddable and syndicated in the request',
    () async {
      final r = await source().find(CommunitySection.edits);
      expect(r, isA<CommunityLoaded>());
      final search = requests.first.queryParameters;
      expect(requests.first.path, endsWith('/search'));
      expect(search['safeSearch'], 'strict');
      expect(search['videoEmbeddable'], 'true');
      expect(search['videoSyndicated'], 'true');
      expect(search['type'], 'video');
      expect(search['regionCode'], 'RU');
      expect(search['q'], 'anime AMV');
      // Проверка каждого ролика — одним videos.list.
      expect(requests[1].path, endsWith('/videos'));
      expect(requests[1].queryParameters['id'], 'a,b');
      expect(requests[1].queryParameters['part'], contains('contentDetails'));
      expect(requests[1].queryParameters['part'], contains('status'));
    },
  );

  test('title query: title + section', () async {
    await source().find(CommunitySection.funny, title: 'Frieren');
    expect(requests.first.queryParameters['q'], 'Frieren funny moments');
  });

  test(
    'age-restricted, non-embeddable and region-blocked videos dropped',
    () async {
      videos = [
        video('ok'),
        video('age', ytRating: 'ytAgeRestricted'),
        video('noembed', embeddable: false),
        video(
          'blocked',
          region: {
            'blocked': ['RU'],
          },
        ),
        video(
          'notallowed',
          region: {
            'allowed': ['US'],
          },
        ),
        video(
          'allowed',
          region: {
            'allowed': ['RU', 'US'],
          },
        ),
      ];
      final r =
          await source().find(CommunitySection.reviews) as CommunityLoaded;
      expect([for (final v in r.videos) v.videoId], ['ok', 'allowed']);
      expect(r.videos.first.isCommunity, isTrue);
      expect(r.videos.first.channel, 'Канал ok');
    },
  );

  test('18+ markers hidden when «Показывать 18+» is off', () async {
    videos = [
      video('ok'),
      video('t', title: 'Best fights [18+]'),
      video('tag', tags: ['anime', 'ecchi']),
    ];
    final c = source();
    final on = await c.find(CommunitySection.edits) as CommunityLoaded;
    expect(on.videos, hasLength(3));
    final off = await c.find(
      CommunitySection.edits,
      showAdult: false,
    ) as CommunityLoaded;
    expect([for (final v in off.videos) v.videoId], ['ok']);
    // Фильтр работает по кэшу — новых запросов нет.
    expect(requests, hasLength(2));
  });

  test(
    '24h cache: no new request within a day, new search the next day',
    () async {
      final c = source();
      await c.find(CommunitySection.edits);
      expect(requests, hasLength(2));
      now = now.add(const Duration(hours: 23));
      final cached = await c.find(CommunitySection.edits) as CommunityLoaded;
      expect(cached.videos, hasLength(2));
      expect(requests, hasLength(2));
      // Другой раздел — свой кэш.
      await c.find(CommunitySection.reviews);
      expect(requests, hasLength(4));
      now = now.add(const Duration(hours: 2));
      await c.find(CommunitySection.edits);
      expect(requests, hasLength(6));
    },
  );

  test('empty result cached 6 hours; one search per day', () async {
    videos = [];
    final c = source();
    final r = await c.find(CommunitySection.funny) as CommunityLoaded;
    expect(r.videos, isEmpty);
    expect(requests, hasLength(1)); // без id videos.list не нужен
    now = now.add(const Duration(hours: 5));
    await c.find(CommunitySection.funny);
    expect(requests, hasLength(1));
    // Пустой кэш устарел, но сегодня уже искали — ждём завтра.
    now = now.add(const Duration(hours: 2));
    final again = await c.find(CommunitySection.funny);
    expect(again, isA<CommunityLoaded>());
    expect(requests, hasLength(1));
    now = DateTime.utc(2026, 11, 13, 1);
    await c.find(CommunitySection.funny);
    expect(requests, hasLength(2));
  });

  test('quota exceeded: result, not a crash; no retry today', () async {
    final c = CommunityVideos(
      apiKey: 'k',
      db: db,
      clock: () => now,
      httpClient: MockClient((r) async {
        requests.add(r.url);
        return http.Response(
          '{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}',
          403,
        );
      }),
    );
    expect(await c.find(CommunitySection.edits), isA<CommunityQuotaExceeded>());
    expect(await c.find(CommunitySection.edits), isA<CommunityQuotaExceeded>());
    expect(requests, hasLength(1));
  });

  test('network error → failed; no key → not configured', () async {
    final c = CommunityVideos(
      apiKey: 'k',
      db: db,
      httpClient: MockClient((_) async => http.Response('oops', 500)),
    );
    expect(await c.find(CommunitySection.edits), isA<CommunityFailed>());
    expect(
      await source(key: '').find(CommunitySection.edits),
      isA<CommunityNotConfigured>(),
    );
    expect(requests, isEmpty);
  });
}
