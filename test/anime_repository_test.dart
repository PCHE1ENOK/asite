import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/anime_repository.dart';
import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/models/catalog_query.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late FakeAniList fake;
  late DateTime now;
  late AnimeRepository repo;
  var offline = false;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    offline = false;
    now = DateTime(2026, 1, 1, 12);
    fake = FakeAniList((body) {
      if (offline) {
        return http.Response('', 503);
      }
      final query = body['query'] as String;
      if (query.contains('query Catalog')) {
        return jsonResponse(fixture('catalog_response.json'));
      }
      if (query.contains('query Details')) {
        return jsonResponse(fixture('details_response.json'));
      }
      return jsonResponse('{"data":{"GenreCollection":["Action"]}}');
    });
    repo = AnimeRepository(
      client: AniListClient(httpClient: fake.client),
      db: db,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  const query = CatalogQuery(sort: AnimeSort.trending);

  test('catalog: network, then fresh cache without network', () async {
    final first = await repo.getCatalog(query);
    expect(first.source, DataSource.network);
    expect(first.data.items.map((a) => a.id), [16498, 154587]);

    now = now.add(const Duration(minutes: 30));
    final second = await repo.getCatalog(query);
    expect(second.source, DataSource.cache);
    expect(second.isStale, isFalse);
    expect(second.data.items.map((a) => a.id), [16498, 154587]);
    expect(second.data.items.first.title.native, '進撃の巨人');
    expect(second.data.pageInfo.hasNextPage, isTrue);
    expect(fake.requests, hasLength(1));
  });

  test('catalog: different filters use different cache keys', () async {
    await repo.getCatalog(query);
    await repo.getCatalog(const CatalogQuery(sort: AnimeSort.score));
    await repo.getCatalog(query, page: 2);
    expect(fake.requests, hasLength(3));
  });

  test('catalog: expired cache is refreshed', () async {
    await repo.getCatalog(query);
    now = now.add(const Duration(hours: 2));
    final result = await repo.getCatalog(query);
    expect(result.source, DataSource.network);
    expect(fake.requests, hasLength(2));
  });

  test('catalog: stale cache is served when offline', () async {
    await repo.getCatalog(query);
    now = now.add(const Duration(days: 2));
    offline = true;

    final result = await repo.getCatalog(query);
    expect(result.source, DataSource.cache);
    expect(result.isStale, isTrue);
    expect(result.data.items, hasLength(2));
  });

  test('catalog: offline without cache throws', () async {
    offline = true;
    await expectLater(repo.getCatalog(query), throwsA(isA<AniListException>()));
  });

  test('details: cached and keeps summary readable', () async {
    final first = await repo.getDetails(16498);
    expect(first.source, DataSource.network);

    final second = await repo.getDetails(16498);
    expect(second.source, DataSource.cache);
    expect(second.data.studios.single.name, 'Wit Studio');
    expect(second.data.relations.single.anime.id, 20958);
    expect(fake.requests, hasLength(1));

    final summary = await repo.getCachedSummary(16498);
    expect(summary?.title.english, 'Attack on Titan');
  });

  test('catalog refresh does not erase cached details', () async {
    await repo.getDetails(16498);
    await repo.getCatalog(query);

    final details = await repo.getDetails(16498);
    expect(details.source, DataSource.cache);
    expect(fake.requests, hasLength(2));
  });

  test('forceRefresh bypasses fresh cache', () async {
    await repo.getDetails(16498);
    final again = await repo.getDetails(16498, forceRefresh: true);
    expect(again.source, DataSource.network);
    expect(fake.requests, hasLength(2));
  });

  test('genres are cached', () async {
    expect((await repo.getGenres()).data, ['Action']);
    expect((await repo.getGenres()).source, DataSource.cache);
    expect(fake.requests, hasLength(1));
  });

  test('prune removes old entries', () async {
    await repo.getCatalog(query);
    now = now.add(const Duration(days: 31));
    await repo.prune();

    expect(await repo.getCachedSummary(16498), isNull);
    offline = true;
    await expectLater(repo.getCatalog(query), throwsA(isA<AniListException>()));
  });

  test('getSummaries: cache first, missing ids fetched by id_in', () async {
    await repo.getCatalog(query); // кладёт 16498 и 154587 в кэш
    fake.handler = (body) {
      expect(body['query'], contains('query ByIds'));
      expect((body['variables'] as Map)['ids'], [999]);
      return jsonResponse(
        '{"data":{"Page":{"pageInfo":{"hasNextPage":false},"media":[{"id":999,"title":{"romaji":"New"}}]}}}',
      );
    };

    final map = await repo.getSummaries([16498, 999]);
    expect(map.keys, unorderedEquals([16498, 999]));
    expect(map[999]!.title.preferred, 'New');
    expect((await repo.getCachedSummary(999))?.title.romaji, 'New');
  });

  test('getSummaries offline returns only cached', () async {
    await repo.getCatalog(query);
    offline = true;
    final map = await repo.getSummaries([16498, 999]);
    expect(map.keys, [16498]);
  });

  test('excludeIds becomes a sorted id_not_in variable', () {
    expect(const CatalogQuery(excludeIds: [5, 2]).toVariables()['excludeIds'], [
      2,
      5,
    ]);
  });
}
