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
  String? language,
}) => {
  'id': id,
  'snippet': {
    'title': title ?? 'Video $id',
    'defaultAudioLanguage': ?audioLanguage,
    'defaultLanguage': ?language,
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

  /// Ролики русского запроса; `null` — те же, что у английского.
  List<Map<String, dynamic>>? ruVideos;
  late DateTime now;

  CommunityVideos source({String key = 'k'}) => CommunityVideos(
    apiKey: key,
    db: db,
    regionCode: 'RU',
    clock: () => now,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      if (r.url.path.endsWith('/search')) {
        final ru = r.url.queryParameters['relevanceLanguage'] == 'ru';
        return json({
          'items': [
            for (final v in (ru ? ruVideos ?? videos : videos))
              {
                'id': {'kind': 'youtube#video', 'videoId': v['id']},
              },
          ],
        });
      }
      final ids = r.url.queryParameters['id']!.split(',');
      return json({
        'items': [
          for (final v in [...videos, ...?ruVideos])
            if (ids.contains(v['id'])) v,
        ],
      });
    }),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    videos = [video('a'), video('b')];
    ruVideos = null;
    now = DateTime.utc(2026, 11, 12, 10);
  });
  tearDown(() => db.close());

  List<Uri> searches() => [
    for (final u in requests)
      if (u.path.endsWith('/search')) u,
  ];

  test('two strict searches: English and Russian words', () async {
    final r = await source().find(CommunitySection.edits);
    expect(r, isA<CommunityLoaded>());
    final s = searches();
    expect(s, hasLength(2));
    for (final u in s) {
      final q = u.queryParameters;
      expect(q['safeSearch'], 'strict');
      expect(q['videoEmbeddable'], 'true');
      expect(q['videoSyndicated'], 'true');
      expect(q['type'], 'video');
      expect(q['regionCode'], 'RU');
    }
    expect(s[0].queryParameters['q'], 'anime AMV');
    expect(s[0].queryParameters['relevanceLanguage'], 'en');
    expect(s[1].queryParameters['q'], 'аниме AMV');
    expect(s[1].queryParameters['relevanceLanguage'], 'ru');
    // Проверка роликов — одним videos.list на запрос.
    final details = requests.where((u) => u.path.endsWith('/videos')).first;
    expect(details.queryParameters['id'], 'a,b');
    expect(details.queryParameters['part'], contains('contentDetails'));
    expect(details.queryParameters['part'], contains('status'));
  });

  test('title queries in both languages', () async {
    final c = source();
    await c.find(CommunitySection.funny, title: 'Frieren', ruTitle: 'Фрирен');
    await c.find(CommunitySection.reviews, title: 'Frieren', ruTitle: 'Фрирен');
    await c.find(CommunitySection.edits, title: 'Frieren');
    expect(
      [for (final u in searches()) u.queryParameters['q']],
      [
        'Frieren funny moments',
        'Фрирен смешные моменты',
        'Frieren review',
        'Фрирен обзор',
        'Frieren AMV',
        'Frieren AMV', // нет русского названия — английское
      ],
    );
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

  test('duplicates found by both searches shown once', () async {
    videos = [video('a'), video('both'), video('b')];
    ruVideos = [video('both'), video('ру', title: 'Ролик по-русски')];
    final r = await source().find(CommunitySection.edits) as CommunityLoaded;
    // Вперемешку: английский, русский, …; «both» — один раз.
    expect([for (final v in r.videos) v.videoId], ['a', 'both', 'ру', 'b']);
  });

  test('language: metadata first, then Cyrillic in the title', () async {
    expect(
      CommunityVideos.languageOf({
        'title': 'AMV',
        'defaultAudioLanguage': 'ru',
      }),
      'RU',
    );
    expect(
      CommunityVideos.languageOf({
        'title': 'Обзор',
        'defaultAudioLanguage': 'en-US',
      }),
      'ENG',
      reason: 'metadata wins over the title',
    );
    expect(
      CommunityVideos.languageOf({'title': 'AMV', 'defaultLanguage': 'ru-RU'}),
      'RU',
    );
    expect(
      CommunityVideos.languageOf({'title': 'ja', 'defaultLanguage': 'ja'}),
      'ENG',
    );
    expect(CommunityVideos.languageOf({'title': 'Смешные моменты'}), 'RU');
    expect(CommunityVideos.languageOf({'title': 'Funny moments'}), 'ENG');

    videos = [
      video('m', audioLanguage: 'ru'),
      video('c', title: 'Эдит под музыку'),
      video('e', title: 'Best edit'),
    ];
    final r = await source().find(CommunitySection.edits) as CommunityLoaded;
    expect(
      {for (final v in r.videos) v.videoId: v.language},
      {'m': 'RU', 'c': 'RU', 'e': 'ENG'},
    );
  });

  test('18+ markers hidden when «Показывать 18+» is off', () async {
    videos = [
      video('ok'),
      video('t', title: 'Best fights [18+]'),
      video('tag', tags: ['anime', 'ecchi']),
    ];
    final c = source();
    final on = await c.find(CommunitySection.edits) as CommunityLoaded;
    expect(on.videos, hasLength(3));
    final n = requests.length;
    final off = await c.find(
      CommunitySection.edits,
      showAdult: false,
    ) as CommunityLoaded;
    expect([for (final v in off.videos) v.videoId], ['ok']);
    // Фильтр работает по кэшу — новых запросов нет.
    expect(requests, hasLength(n));
  });

  test(
    '24h cache: no new request within a day, new search the next day',
    () async {
      final c = source();
      await c.find(CommunitySection.edits);
      expect(searches(), hasLength(2));
      now = now.add(const Duration(hours: 23));
      final cached = await c.find(CommunitySection.edits) as CommunityLoaded;
      expect(cached.videos, hasLength(2));
      expect(searches(), hasLength(2));
      // Другой раздел — свой кэш.
      await c.find(CommunitySection.reviews);
      expect(searches(), hasLength(4));
      now = now.add(const Duration(hours: 2));
      await c.find(CommunitySection.edits);
      expect(searches(), hasLength(6));
    },
  );

  test('empty result cached 6 hours; one search per day', () async {
    videos = [];
    final c = source();
    final r = await c.find(CommunitySection.funny) as CommunityLoaded;
    expect(r.videos, isEmpty);
    expect(requests, hasLength(2)); // без id videos.list не нужен
    now = now.add(const Duration(hours: 5));
    await c.find(CommunitySection.funny);
    expect(requests, hasLength(2));
    // Пустой кэш устарел, но сегодня уже искали — ждём завтра.
    now = now.add(const Duration(hours: 2));
    final again = await c.find(CommunitySection.funny);
    expect(again, isA<CommunityLoaded>());
    expect(requests, hasLength(2));
    now = DateTime.utc(2026, 11, 13, 1);
    await c.find(CommunitySection.funny);
    expect(requests, hasLength(4));
  });

  test('quota exceeded on both: result, not a crash; no retry today', () async {
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
    expect(requests, hasLength(2));
    expect(await c.find(CommunitySection.edits), isA<CommunityQuotaExceeded>());
    expect(requests, hasLength(2));
  });

  test('quota checked per request: English out, Russian still shown', () async {
    var quotaOut = true;
    final c = CommunityVideos(
      apiKey: 'k',
      db: db,
      clock: () => now,
      httpClient: MockClient((r) async {
        requests.add(r.url);
        final ru = r.url.queryParameters['relevanceLanguage'] == 'ru';
        if (r.url.path.endsWith('/search')) {
          if (!ru && quotaOut) {
            return http.Response(
              '{"error":{"errors":[{"reason":"quotaExceeded"}]}}',
              403,
            );
          }
          return json({
            'items': [
              {
                'id': {'videoId': ru ? 'r1' : 'e1'},
              },
            ],
          });
        }
        final id = r.url.queryParameters['id']!;
        return json({
          'items': [video(id, title: id == 'r1' ? 'Обзор' : 'Review')],
        });
      }),
    );
    final r = await c.find(CommunitySection.reviews) as CommunityLoaded;
    expect([for (final v in r.videos) '${v.videoId}:${v.language}'], ['r1:RU']);
    // Квота вернулась, но английский уже пробовали сегодня — не ищем;
    // русский — из кэша.
    quotaOut = false;
    final n = requests.length;
    final again = await c.find(CommunitySection.reviews) as CommunityLoaded;
    expect(again.videos, hasLength(1));
    expect(requests, hasLength(n));
    // Завтра английский ищется снова, русский — ещё в кэше (сутки не прошли).
    now = DateTime.utc(2026, 11, 13, 1);
    final next = await c.find(CommunitySection.reviews) as CommunityLoaded;
    expect([for (final v in next.videos) v.videoId], ['e1', 'r1']);
    expect(
      [
        for (final u in requests.skip(n))
          u.queryParameters['relevanceLanguage'],
      ],
      ['en', null],
    );
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
