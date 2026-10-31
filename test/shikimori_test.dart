import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/shikimori/russian_text.dart';
import 'package:anime_viewer/data/shikimori/shikimori_client.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Anime anime(int id, {int? mal}) => Anime(
  id: id,
  idMal: mal,
  title: AnimeTitle(romaji: 'T$id'),
);

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late List<http.Request> requests;
  late http.Response Function(Uri) handler;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    requests = [];
    now = DateTime.utc(2026, 10, 31);
    handler = (_) => json([]);
  });
  tearDown(() => db.close());

  RussianTextRepository repo() => RussianTextRepository(
    db: db,
    clock: () => now,
    client: ShikimoriClient(
      minInterval: Duration.zero,
      httpClient: MockClient((r) async {
        requests.add(r);
        return handler(r.url);
      }),
    ),
  );

  test('description markup is removed', () {
    expect(
      ShikiAnime.plainDescription(
        '[character=1]Эрен[/character] клянётся [i]уничтожить[/i] '
        '[[титанов]].\r\n\r\n\r\n[spoiler=спойлер]Тайна[/spoiler]',
      ),
      'Эрен клянётся уничтожить титанов.\n\nТайна',
    );
  });

  test('parsing: year, empty strings, garbage', () {
    final a = ShikiAnime.fromJson({
      'id': 5,
      'russian': ' ',
      'name': 'Shingeki',
      'aired_on': '2013-04-07',
    })!;
    expect(a.russian, isNull);
    expect(a.year, 2013);
    expect(ShikiAnime.fromJson('x'), isNull);
    expect(ShikiAnime.fromJson({'id': 'x'}), isNull);
  });

  test('titles: one request per 50, user agent, cached for 7 days', () async {
    handler = (u) => json([
      {'id': 11, 'russian': 'Атака титанов'},
      {'id': 12, 'russian': ''},
    ]);
    final r = repo();
    final items = [anime(1, mal: 11), anime(2, mal: 12), anime(3)];
    expect(await r.titles(items), {1: 'Атака титанов'});
    expect(requests, hasLength(1));
    expect(requests.single.url.queryParameters['ids'], '11,12');
    expect(requests.single.headers['User-Agent'], ShikimoriClient.userAgent);

    now = now.add(const Duration(days: 6));
    expect(await r.titles(items), {1: 'Атака титанов'});
    expect(requests, hasLength(1), reason: 'cached, incl. «no russian»');

    now = now.add(const Duration(days: 2));
    await r.titles(items);
    expect(requests, hasLength(2), reason: 'expired after 7 days');
  });

  test('network errors and rate limits are not cached', () async {
    handler = (_) => http.Response('', 429);
    final r = repo();
    expect(await r.titles([anime(1, mal: 11)]), isEmpty);
    handler = (_) => json([
      {'id': 11, 'russian': 'Атака титанов'},
    ]);
    expect(await r.titles([anime(1, mal: 11)]), {1: 'Атака титанов'});
    expect(await r.details(AnimeDetails(anime: anime(1, mal: 11))), isNotNull);
  });

  test('details by MAL id: russian title and plain description', () async {
    handler = (u) {
      expect(u.path, '/api/animes/16498');
      return json({
        'id': 16498,
        'russian': 'Атака титанов',
        'description': '[character=1]Эрен[/character] живёт за стенами.',
      });
    };
    final d = (await repo().details(
      AnimeDetails(anime: anime(1, mal: 16498)),
    ))!;
    expect(d.title, 'Атака титанов');
    expect(d.description, 'Эрен живёт за стенами.');
    // Название попало и в кэш списков.
    requests.clear();
    expect(await repo().titles([anime(1, mal: 16498)]), {1: 'Атака титанов'});
    expect(requests, isEmpty);
  });

  test('no MAL id: search by title and year', () async {
    handler = (u) {
      if (u.path == '/api/animes') {
        return json([
          {'id': 1, 'name': 'Dandadan', 'aired_on': '2019-01-01'},
          {'id': 2, 'name': 'Dandadan', 'aired_on': '2024-10-04'},
        ]);
      }
      return json({'id': 2, 'russian': 'Дандадан'});
    };
    final d = await repo().details(
      AnimeDetails(
        anime: const Anime(
          id: 9,
          seasonYear: 2024,
          title: AnimeTitle(romaji: 'Dandadan', english: 'DAN DA DAN'),
        ),
      ),
    );
    expect(d!.title, 'Дандадан');
    expect(requests.last.url.path, '/api/animes/2');
  });

  test('not on Shikimori: empty, cached', () async {
    handler = (_) => http.Response('', 404);
    final d = await repo().details(AnimeDetails(anime: anime(1, mal: 5)));
    expect(d!.isEmpty, isTrue);
    await repo().details(AnimeDetails(anime: anime(1, mal: 5)));
    expect(requests, hasLength(1));
  });
}
