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
  String? audioLanguage,
  String duration = 'PT3M12S',
}) => {
  'id': id,
  'snippet': {
    'title': title ?? 'Ролик $id',
    'channelTitle': 'Канал $id',
    'tags': tags,
    'defaultAudioLanguage': ?audioLanguage,
    'thumbnails': {
      'medium': {'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg'},
    },
  },
  'contentDetails': {
    'duration': duration,
    'contentRating': {'ytRating': ?ytRating},
    'regionRestriction': ?region,
  },
  'status': {'embeddable': embeddable, 'privacyStatus': 'public'},
};

http.Response json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

http.Response quota() => http.Response(
  '{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}',
  403,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late List<Uri> requests;

  /// Ролики по запросу; нет запроса в карте — [videos].
  late Map<String, List<Map<String, dynamic>>> byQuery;
  late List<Map<String, dynamic>> videos;

  /// Запросы, на которые YouTube отвечает «квота кончилась».
  late Set<String> quotaFor;
  late DateTime now;

  CommunityVideos source({String key = 'k'}) => CommunityVideos(
    apiKey: key,
    db: db,
    regionCode: 'RU',
    clock: () => now,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      final q = r.url.queryParameters['q'];
      if (r.url.path.endsWith('/search')) {
        if (quotaFor.contains(q)) return quota();
        return json({
          'items': [
            for (final v in byQuery[q] ?? videos)
              {
                'id': {'kind': 'youtube#video', 'videoId': v['id']},
              },
          ],
        });
      }
      final ids = r.url.queryParameters['id']!.split(',');
      final all = [...videos, for (final l in byQuery.values) ...l];
      return json({
        'items': [for (final id in ids) all.firstWhere((v) => v['id'] == id)],
      });
    }),
  );

  List<Uri> searches() => [
    for (final u in requests)
      if (u.path.endsWith('/search')) u,
  ];
  List<String?> queries() => [
    for (final u in searches()) u.queryParameters['q'],
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    byQuery = {};
    videos = [video('a'), video('b')];
    quotaFor = {};
    now = DateTime.utc(2026, 11, 12, 10);
  });
  tearDown(() => db.close());

  test('«Пересказ аниме» is the first section', () {
    expect(CommunitySection.values.first, CommunitySection.retell);
    expect(CommunitySection.values.map((s) => s.label), [
      'Пересказ аниме',
      'Эдиты',
      'Обзоры',
      'Смешные моменты',
    ]);
  });

  test('retell: «Переозвучка …» and «… за 15 минут», Russian only, '
      'strict', () async {
    final r = await source().find(CommunitySection.retell, title: 'Фрирен');
    expect(r, isA<CommunityLoaded>());
    expect(queries(), ['Переозвучка Фрирен', 'Фрирен за 15 минут']);
    for (final u in searches()) {
      final q = u.queryParameters;
      expect(q['relevanceLanguage'], 'ru');
      expect(q['safeSearch'], 'strict');
      expect(q['videoEmbeddable'], 'true');
      expect(q['videoSyndicated'], 'true');
      expect(q['type'], 'video');
      expect(q['regionCode'], 'RU');
    }
    // Один ролик в обоих запросах — один раз.
    expect((r as CommunityLoaded).videos.map((v) => v.videoId), ['a', 'b']);
    expect(r.videos.first.category, 'Пересказ аниме');
  });

  test('other sections: one Russian query each, no English search', () async {
    final c = source();
    for (final s in [
      CommunitySection.edits,
      CommunitySection.reviews,
      CommunitySection.funny,
    ]) {
      await c.find(s, title: 'Sousou no Frieren');
    }
    expect(queries(), [
      'Sousou no Frieren AMV',
      'Sousou no Frieren обзор',
      'Sousou no Frieren смешные моменты',
    ]);
    expect(
      searches().map((u) => u.queryParameters['relevanceLanguage']).toSet(),
      {'ru'},
    );
    expect(queries().any((q) => q!.contains('review')), isFalse);
    expect(queries().any((q) => q!.contains('funny moments')), isFalse);
  });

  test(
    'dropped: age-restricted, not embeddable, region, not Russian',
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
        video('english', title: 'Frieren AMV best edit'),
        video('meta', title: 'Frieren AMV', audioLanguage: 'ru'),
        video('meta-en', title: 'Frieren AMV', audioLanguage: 'en'),
      ];
      final r = await source().find(
        CommunitySection.edits,
        title: 'Фрирен',
      ) as CommunityLoaded;
      expect(r.videos.map((v) => v.videoId), ['ok', 'meta']);
      expect(r.videos.first.isCommunity, isTrue);
      expect(r.videos.first.channel, 'Канал ok');
    },
  );

  test('duration from contentDetails', () async {
    videos = [
      video('short', duration: 'PT3M12S'),
      video('long', duration: 'PT1H2M5S'),
      video('live', duration: 'P0D'),
    ];
    final r = await source().find(
      CommunitySection.retell,
      title: 'Т',
    ) as CommunityLoaded;
    expect(
      {for (final v in r.videos) v.videoId: v.duration},
      {
        'short': const Duration(minutes: 3, seconds: 12),
        'long': const Duration(hours: 1, minutes: 2, seconds: 5),
        'live': null,
      },
    );
    expect(CommunityVideos.parseDuration('PT15M'), const Duration(minutes: 15));
    expect(CommunityVideos.parseDuration('P1DT2H'), const Duration(hours: 26));
    expect(CommunityVideos.parseDuration('junk'), isNull);
  });

  test('18+ markers hidden when «Показывать 18+» is off', () async {
    videos = [
      video('ok'),
      video('t', title: 'Лучшие бои [18+]'),
      video('tag', tags: ['аниме', 'ecchi']),
    ];
    final c = source();
    final on =
        await c.find(CommunitySection.edits, title: 'Т') as CommunityLoaded;
    expect(on.videos, hasLength(3));
    final n = requests.length;
    final off = await c.find(
      CommunitySection.edits,
      title: 'Т',
      showAdult: false,
    ) as CommunityLoaded;
    expect(off.videos.map((v) => v.videoId), ['ok']);
    expect(requests, hasLength(n), reason: 'фильтр по кэшу');
  });

  test('24h cache per query: no new request within a day', () async {
    final c = source();
    await c.find(CommunitySection.retell, title: 'Т');
    expect(searches(), hasLength(2));
    now = now.add(const Duration(hours: 23));
    final cached =
        await c.find(CommunitySection.retell, title: 'Т') as CommunityLoaded;
    expect(cached.videos, hasLength(2));
    expect(searches(), hasLength(2));
    // Другой тайтл — свой кэш.
    await c.find(CommunitySection.retell, title: 'Другой');
    expect(searches(), hasLength(4));
    now = now.add(const Duration(hours: 2));
    await c.find(CommunitySection.retell, title: 'Т');
    expect(searches(), hasLength(6));
  });

  test('empty section: cached 6 hours, one search per day', () async {
    videos = [];
    final c = source();
    final r = await c.find(CommunitySection.funny, title: 'Т');
    expect((r as CommunityLoaded).videos, isEmpty);
    expect(requests, hasLength(1)); // без id videos.list не нужен
    now = now.add(const Duration(hours: 5));
    await c.find(CommunitySection.funny, title: 'Т');
    expect(requests, hasLength(1));
    now = now.add(const Duration(hours: 2));
    await c.find(CommunitySection.funny, title: 'Т');
    expect(requests, hasLength(1), reason: 'сегодня уже искали');
    now = DateTime.utc(2026, 11, 13, 1);
    await c.find(CommunitySection.funny, title: 'Т');
    expect(requests, hasLength(2));
  });

  test('quota on every Russian query: no crash, no retry today', () async {
    quotaFor = {'Т AMV'};
    final c = source();
    expect(
      await c.find(CommunitySection.edits, title: 'Т'),
      isA<CommunityQuotaExceeded>(),
    );
    expect(searches(), hasLength(1));
    quotaFor = {};
    expect(
      await c.find(CommunitySection.edits, title: 'Т'),
      isA<CommunityQuotaExceeded>(),
    );
    expect(searches(), hasLength(1));
  });

  test('quota checked per query: the other retell query still shown', () async {
    quotaFor = {'Переозвучка Т'};
    final r = await source().find(
      CommunitySection.retell,
      title: 'Т',
    ) as CommunityLoaded;
    expect(r.videos, hasLength(2));
    expect(r.quotaHit, isTrue);
  });

  test('quota with an expired cache: old videos with a warning', () async {
    final c = source();
    await c.find(CommunitySection.edits, title: 'Т');
    now = DateTime.utc(2026, 11, 14, 10);
    quotaFor = {'Т AMV'};
    final r =
        await c.find(CommunitySection.edits, title: 'Т') as CommunityLoaded;
    expect(r.videos, hasLength(2));
    expect(r.quotaHit, isTrue);
  });

  test('quota resets at midnight Pacific time', () {
    // Ноябрь — PST (UTC−8): полночь = 08:00 UTC.
    expect(
      CommunityVideos.quotaResetAfter(DateTime.utc(2026, 11, 12, 10)).toUtc(),
      DateTime.utc(2026, 11, 13, 8),
    );
    // До полуночи по Тихоокеанскому — сегодняшняя полночь (по UTC — завтра).
    expect(
      CommunityVideos.quotaResetAfter(DateTime.utc(2026, 11, 13, 7)).toUtc(),
      DateTime.utc(2026, 11, 13, 8),
    );
    // Июль — PDT (UTC−7): 07:00 UTC.
    expect(
      CommunityVideos.quotaResetAfter(DateTime.utc(2026, 7, 1, 12)).toUtc(),
      DateTime.utc(2026, 7, 2, 7),
    );
  });

  test('network error → failed; no key → not configured', () async {
    final c = CommunityVideos(
      apiKey: 'k',
      db: db,
      httpClient: MockClient((_) async => http.Response('oops', 500)),
    );
    expect(
      await c.find(CommunitySection.edits, title: 'Т'),
      isA<CommunityFailed>(),
    );
    expect(
      await source(key: '').find(CommunitySection.edits, title: 'Т'),
      isA<CommunityNotConfigured>(),
    );
    expect(requests, isEmpty);
  });
}
