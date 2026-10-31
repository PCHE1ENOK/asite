import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:anime_viewer/data/sources/youtube_match.dart';
import 'package:anime_viewer/data/sources/youtube_source.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AnimeDetails frieren({String format = 'TV'}) => AnimeDetails(
  anime: Anime(
    id: 154587,
    format: format,
    title: const AnimeTitle(
      romaji: 'Sousou no Frieren',
      english: "Frieren: Beyond Journey's End",
    ),
  ),
);

Map<String, dynamic> item(String id, String title) => {
  'id': {'kind': 'youtube#video', 'videoId': id},
  'snippet': {
    'title': title,
    'thumbnails': {
      'medium': {'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg'},
    },
  },
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late List<Uri> requests;
  late http.Response Function(Uri) handler;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    handler = (uri) {
      if (uri.path.endsWith('/channels')) {
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'UC-${uri.queryParameters['forHandle']}'},
            ],
          }),
          200,
        );
      }
      final channel = uri.queryParameters['channelId']!;
      if (channel == 'UC-@MuseAsia') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                item(
                  'e2',
                  'Frieren: Beyond Journey&#39;s End - Episode 2 [English Sub]',
                ),
                item('e1', 'Frieren: Beyond Journey&#39;s End EP01'),
                item('pv', 'Sousou no Frieren | Official Trailer'),
                item('x', 'Another Show Episode 3'),
              ],
            }),
          ),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            item('dup', 'Sousou no Frieren #2'),
            item('e3', 'Sousou no Frieren #3'),
          ],
        }),
        200,
      );
    };
  });
  tearDown(() => db.close());

  YouTubeSource source({String key = 'k', String? region}) => YouTubeSource(
    apiKey: key,
    db: db,
    regionCode: region,
    httpClient: MockClient((r) async {
      requests.add(r.url);
      return handler(r.url);
    }),
  );

  test('without an API key the source is empty and does no requests', () async {
    final s = source(key: '');
    expect(s.isConfigured, isFalse);
    expect(await s.find(frieren()), isEmpty);
    expect(await const VideoSources([]).find(frieren()), isEmpty);
    expect(await VideoSources([s]).find(frieren()), isEmpty);
    expect(requests, isEmpty);
  });

  test('finds official episodes, one per episode, sorted', () async {
    final videos = await source(region: 'RU').find(frieren());

    expect(videos.map((v) => (v.episode, v.videoId)), [
      (1, 'e1'),
      (2, 'e2'),
      (3, 'e3'),
    ]);
    expect(videos.first.channel, 'Muse Asia');
    expect(
      videos[1].title,
      "Frieren: Beyond Journey's End - Episode 2 [English Sub]",
    );

    final search = requests.where((u) => u.path.endsWith('/search')).toList();
    expect(search, hasLength(2));
    expect(
      search.first.queryParameters,
      containsPair('videoEmbeddable', 'true'),
    );
    expect(search.first.queryParameters, containsPair('type', 'video'));
    expect(search.first.queryParameters, containsPair('regionCode', 'RU'));
    expect(search.first.queryParameters, containsPair('key', 'k'));
  });

  test('only official embed and watch URLs, no direct streams', () async {
    final videos = await source().find(frieren());
    expect(videos, isNotEmpty);
    for (final v in videos) {
      expect(v.embedUrl.host, 'www.youtube.com');
      expect(v.embedUrl.path, '/embed/${v.videoId}');
      expect(
        v.watchUrl.toString(),
        'https://www.youtube.com/watch?v=${v.videoId}',
      );
      for (final u in [v.embedUrl, v.watchUrl]) {
        expect(u.path, isNot(matches(r'\.(m3u8|mpd|mp4|webm|ts)$')));
      }
    }
  });

  test('results are cached: second lookup makes no requests', () async {
    final s = source();
    await s.find(frieren());
    final before = requests.length;
    expect(await s.find(frieren()), hasLength(3));
    expect(requests.length, before);
  });

  test('empty results are kept 6 hours, found ones 3 days', () async {
    var now = DateTime.utc(2026, 10, 31, 8);
    YouTubeSource at() => YouTubeSource(
      apiKey: 'k',
      db: db,
      clock: () => now,
      httpClient: MockClient((r) async {
        requests.add(r.url);
        return handler(r.url);
      }),
    );
    int searches() => requests.where((u) => u.path.endsWith('/search')).length;

    // Нашлось: через 7 часов — из кэша.
    expect(await at().find(frieren()), hasLength(3));
    final found = searches();
    now = now.add(const Duration(hours: 7));
    expect(await at().find(frieren()), hasLength(3));
    expect(searches(), found);

    // Ничего подходящего: через час — из кэша, через 7 часов — заново.
    final other = AnimeDetails(
      anime: const Anime(
        id: 1,
        format: 'TV',
        title: AnimeTitle(romaji: 'Dandadan'),
      ),
    );
    expect(await at().find(other), isEmpty);
    final empty = searches();
    now = now.add(const Duration(hours: 1));
    expect(await at().find(other), isEmpty);
    expect(searches(), empty);
    now = now.add(const Duration(hours: 6));
    await at().find(other);
    expect(searches(), empty + 2);
  });

  test('trailer titles: openings, clips and episodes are filtered out', () {
    final f = frieren();
    for (final t in [
      'Sousou no Frieren | Official Trailer',
      "Frieren: Beyond Journey's End Season 2 - Teaser",
      'Sousou no Frieren PV2',
      'Sousou no Frieren - Main Trailer [English Sub]',
    ]) {
      expect(YouTubeMatch.isTrailerFor(t, f), isTrue, reason: t);
    }
    for (final t in [
      'Sousou no Frieren Opening | Yuusha',
      'Sousou no Frieren - Creditless Ending',
      'Sousou no Frieren Music Video PV',
      'Sousou no Frieren OP PV',
      'Sousou no Frieren Episode 3 Preview Trailer',
      'Sousou no Frieren clip: Himmel',
      'Sousou no Frieren',
      'Another Show | Official Trailer',
    ]) {
      expect(YouTubeMatch.isTrailerFor(t, f), isFalse, reason: t);
    }
  });

  test('trailer: only trailer channels, first real trailer, cached', () async {
    final asked = <String>[];
    handler = (uri) {
      if (uri.path.endsWith('/channels')) {
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'UC-${uri.queryParameters['forHandle']}'},
            ],
          }),
          200,
        );
      }
      asked.add(uri.queryParameters['channelId']!);
      expect(uri.queryParameters['q'], 'Sousou no Frieren trailer|PV|teaser');
      expect(uri.queryParameters, containsPair('videoEmbeddable', 'true'));
      return http.Response(
        jsonEncode({
          'items': uri.queryParameters['channelId'] == 'UC-@Crunchyroll'
              ? [
                  item('op', 'Sousou no Frieren Opening | Yuusha'),
                  item('mv', 'Sousou no Frieren Music Video'),
                ]
              : [
                  item('tr', 'Sousou no Frieren | Official Trailer'),
                  item('tr2', 'Sousou no Frieren PV2'),
                ],
        }),
        200,
      );
    };
    final s = source(region: 'RU');
    final t = (await s.findTrailer(frieren()))!;
    expect(t.videoId, 'tr');
    expect(t.isTrailer, isTrue);
    expect(t.episode, isNull);
    expect(t.channel, 'Netflix Anime');
    expect(t.embedUrl.path, '/embed/tr');
    expect(asked, ['UC-@Crunchyroll', 'UC-@NetflixAnime']);
    expect(
      asked.any((c) => c.contains('MuseAsia') || c.contains('AniOne')),
      isFalse,
    );

    await s.findTrailer(frieren());
    expect(asked, hasLength(2), reason: 'cached');
    // Серии с каналов трейлеров не берутся.
    expect(await s.find(frieren()), isEmpty);
  });

  test('no trailer: null, no exception', () async {
    handler = (_) => http.Response('{"error":{"code":403}}', 403);
    expect(await source().findTrailer(frieren()), isNull);
    expect(await source(key: '').findTrailer(frieren()), isNull);
  });

  test('refresh ignores the cache', () async {
    final s = source();
    await s.find(frieren());
    final before = requests.where((u) => u.path.endsWith('/search')).length;
    expect(await s.find(frieren(), refresh: true), hasLength(3));
    expect(
      requests.where((u) => u.path.endsWith('/search')).length,
      before + 2,
    );
  });

  test(
    'API errors (quota, network) give an empty result, not an exception',
    () async {
      handler = (_) => http.Response(
        '{"error":{"code":403,"message":"quotaExceeded"}}',
        403,
      );
      expect(await source().find(frieren()), isEmpty);
    },
  );

  test('movies may use a video without an episode number', () async {
    handler = (uri) => uri.path.endsWith('/channels')
        ? http.Response('{"items":[{"id":"UC1"}]}', 200)
        : http.Response(
            jsonEncode({
              'items': [item('m', 'Sousou no Frieren The Movie | Full')],
            }),
            200,
          );
    final s = YouTubeSource(
      apiKey: 'k',
      db: db,
      channels: const [OfficialChannel('@MuseAsia', 'Muse Asia')],
      httpClient: MockClient((r) async => handler(r.url)),
    );
    expect((await s.find(frieren(format: 'MOVIE'))).single.videoId, 'm');
    expect(
      await s.find(frieren()),
      isEmpty,
      reason: 'TV needs episode numbers',
    );
  });

  test('episode number and title matching', () {
    expect(YouTubeSource.episodeNumber('Show - Episode 12 [Eng Sub]'), 12);
    expect(YouTubeSource.episodeNumber('Show EP05'), 5);
    expect(YouTubeSource.episodeNumber('Show Ep. 7'), 7);
    expect(YouTubeSource.episodeNumber('Show #003'), 3);
    expect(YouTubeSource.episodeNumber('Show | Official Trailer'), isNull);
    expect(
      YouTubeSource.matchesTitle('SOUSOU NO FRIEREN ep 1', frieren()),
      isTrue,
    );
    expect(
      YouTubeSource.matchesTitle('Some other anime ep 1', frieren()),
      isFalse,
    );
  });

  test('matched name is reported for diagnostics', () {
    final names = YouTubeMatch.titleNames(frieren());
    expect(names, everyElement(hasLength(greaterThanOrEqualTo(4))));
    expect(names.toSet().length, names.length, reason: 'no duplicates');
    expect(
      YouTubeMatch.matchedName('SOUSOU NO FRIEREN ep 1', frieren()),
      isNotNull,
    );
    expect(YouTubeMatch.matchedName('Other ep 1', frieren()), isNull);
  });

  test(
    'source selection: unconfigured skipped, first with results wins',
    () async {
      final a = _Fixed(configured: false, videos: [_v('a')]);
      final b = _Fixed(configured: true, videos: const []);
      final c = _Fixed(configured: true, videos: [_v('c')]);
      final d = _Fixed(configured: true, videos: [_v('d')]);
      final sources = VideoSources([a, b, c, d]);
      expect(sources.anyConfigured, isTrue);
      expect((await sources.find(frieren())).single.videoId, 'c');
      expect(a.calls, 0);
      expect(d.calls, 0);
      expect(const VideoSources([]).anyConfigured, isFalse);
    },
  );
}

EmbeddedVideo _v(String id) => EmbeddedVideo(
  sourceId: 'x',
  videoId: id,
  title: id,
  channel: 'c',
  episode: 1,
);

class _Fixed implements VideoSource {
  _Fixed({required this.configured, required this.videos});

  final bool configured;
  final List<EmbeddedVideo> videos;
  var calls = 0;

  @override
  String get id => 'fixed';

  @override
  String get name => 'Fixed';

  @override
  bool get isConfigured => configured;

  @override
  Future<EmbeddedVideo?> findTrailer(
    AnimeDetails title, {
    bool refresh = false,
  }) async => null;

  @override
  Future<List<EmbeddedVideo>> find(
    AnimeDetails title, {
    bool refresh = false,
  }) async {
    calls++;
    return videos;
  }
}
