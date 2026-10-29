import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/models/catalog_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fixtures.dart';

void main() {
  group('fetchCatalog', () {
    test('parses page info and media', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(fixture('catalog_response.json')),
      );
      final client = AniListClient(httpClient: fake.client);

      final page = await client.fetchCatalog(const CatalogQuery());

      expect(page.pageInfo.currentPage, 1);
      expect(page.pageInfo.hasNextPage, isTrue);
      expect(page.pageInfo.total, 5000);
      expect(page.items, hasLength(2));

      final aot = page.items.first;
      expect(aot.id, 16498);
      expect(aot.title.preferred, 'Attack on Titan');
      expect(aot.title.native, '進撃の巨人');
      expect(aot.coverImage.best, endsWith('/large/bx16498-73IhOXpJZiMF.jpg'));
      expect(aot.format, 'TV');
      expect(aot.season, 'SPRING');
      expect(aot.seasonYear, 2013);
      expect(aot.genres, ['Action', 'Drama', 'Fantasy', 'Mystery']);
      expect(aot.score10, 8.5);

      final frieren = page.items.last;
      expect(frieren.title.preferred, 'Sousou no Frieren');
      expect(frieren.coverImage.best, endsWith('bx154587.jpg'));
      expect(frieren.averageScore, isNull);
      expect(frieren.score10, 9.0, reason: 'falls back to meanScore');
    });

    test('sends filters and pagination as variables', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(fixture('catalog_response.json')),
      );
      final client = AniListClient(httpClient: fake.client);

      await client.fetchCatalog(
        const CatalogQuery(
          sort: AnimeSort.score,
          genres: ['Action'],
          formats: ['TV', 'MOVIE'],
          season: 'FALL',
          seasonYear: 2023,
          minScore: 70,
        ),
        page: 3,
        perPage: 20,
      );

      final vars = fake.requests.single['variables'] as Map<String, dynamic>;
      expect(vars, {
        'sort': ['SCORE_DESC'],
        'genres': ['Action'],
        'formats': ['TV', 'MOVIE'],
        'season': 'FALL',
        'seasonYear': 2023,
        'minScore': 70,
        'page': 3,
        'perPage': 20,
      });
      expect(fake.requests.single['query'], contains('query Catalog'));
    });

    test('search sorts by relevance and trims text', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(fixture('catalog_response.json')),
      );
      final client = AniListClient(httpClient: fake.client);

      await client.search('  frieren ');

      final vars = fake.requests.single['variables'] as Map<String, dynamic>;
      expect(vars['search'], 'frieren');
      expect(vars['sort'], ['SEARCH_MATCH']);
    });
  });

  group('fetchDetails', () {
    test('parses full card', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(fixture('details_response.json')),
      );
      final client = AniListClient(httpClient: fake.client);

      final d = await client.fetchDetails(16498);

      expect(fake.requests.single['variables'], {'id': 16498});
      expect(d.id, 16498);
      expect(d.anime.averageScore, 85);
      expect(
        d.plainDescription,
        'Several hundred years ago, humans were nearly exterminated by '
        'Titans.\n\n\nTitans are typically several stories tall & seem to '
        'have no intelligence.',
      );
      expect(d.startDate.toString(), '2013-04-07');
      expect(d.endDate?.month, 9);
      expect(d.synonyms, ['AoT', 'SnK']);
      expect(d.source, 'MANGA');
      expect(d.studios.single.name, 'Wit Studio');
      expect(d.studios.single.isMain, isTrue);
      expect(d.tags.map((t) => t.isSpoiler), [false, true]);
      expect(d.scoreDistribution.last.score, 100);
      expect(d.scoreDistribution.last.amount, 98000);
      expect(d.trailer?.site, 'youtube');
      expect(d.nextAiringEpisode, isNull);

      // Манга из связей отбрасывается, остаётся только аниме.
      expect(d.relations, hasLength(1));
      expect(d.relations.single.relationType, 'SEQUEL');
      expect(d.relations.single.anime.id, 20958);

      // Пустая рекомендация пропускается.
      expect(d.recommendations.single.id, 101922);
      expect(d.raw['id'], 16498);
    });

    test('parses next airing episode', () async {
      final fake = FakeAniList(
        (_) => jsonResponse('''
        {"data": {"Media": {"id": 1, "title": {"romaji": "X"},
          "nextAiringEpisode": {"episode": 5, "airingAt": 1700000000}}}}
      '''),
      );
      final d = await AniListClient(httpClient: fake.client).fetchDetails(1);

      expect(d.nextAiringEpisode?.episode, 5);
      expect(
        d.nextAiringEpisode?.airingAt,
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
      expect(d.studios, isEmpty);
      expect(d.anime.genres, isEmpty);
    });

    test('maps GraphQL 404 to AniListException.isNotFound', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(fixture('not_found_response.json'), status: 404),
      );
      final client = AniListClient(httpClient: fake.client);

      await expectLater(
        client.fetchDetails(999999999),
        throwsA(
          isA<AniListException>()
              .having((e) => e.isNotFound, 'isNotFound', isTrue)
              .having((e) => e.message, 'message', 'Not Found.'),
        ),
      );
    });
  });

  group('errors', () {
    test('GraphQL errors with HTTP 200 are thrown', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(
          '{"errors":[{"message":"Bad","status":400}],"data":null}',
        ),
      );
      await expectLater(
        AniListClient(httpClient: fake.client).fetchGenres(),
        throwsA(
          isA<AniListException>().having((e) => e.statusCode, 'status', 400),
        ),
      );
    });

    test('non-JSON body is reported with HTTP status', () async {
      final fake = FakeAniList((_) => http.Response('<html>oops</html>', 502));
      await expectLater(
        AniListClient(httpClient: fake.client).fetchGenres(),
        throwsA(
          isA<AniListException>()
              .having((e) => e.statusCode, 'status', 502)
              .having((e) => e.message, 'message', 'HTTP 502'),
        ),
      );
    });

    test('retries once after 429 with Retry-After', () async {
      var calls = 0;
      final fake = FakeAniList((_) {
        calls++;
        if (calls == 1) {
          return jsonResponse(
            '{"errors":[{"message":"Too Many Requests.","status":429}],"data":null}',
            status: 429,
            headers: {'retry-after': '0'},
          );
        }
        return jsonResponse('{"data":{"GenreCollection":["Action","Drama"]}}');
      });

      final genres = await AniListClient(httpClient: fake.client).fetchGenres();

      expect(genres, ['Action', 'Drama']);
      expect(calls, 2);
    });

    test('does not wait when Retry-After exceeds the limit', () async {
      final fake = FakeAniList(
        (_) => jsonResponse(
          '{"errors":[{"message":"Too Many Requests.","status":429}],"data":null}',
          status: 429,
          headers: {'retry-after': '120'},
        ),
      );
      final client = AniListClient(httpClient: fake.client);

      await expectLater(
        client.fetchGenres(),
        throwsA(
          isA<AniListException>()
              .having((e) => e.isRateLimited, 'isRateLimited', isTrue)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 120),
              ),
        ),
      );
      expect(fake.requests, hasLength(1));
    });

    test('network failure becomes AniListException', () async {
      final client = AniListClient(httpClient: _ThrowingClient());
      await expectLater(client.fetchGenres(), throwsA(isA<AniListException>()));
    });
  });
}

class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw http.ClientException('offline', request.url);
}
