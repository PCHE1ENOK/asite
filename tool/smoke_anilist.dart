// Ручная проверка реальных запросов к AniList: dart run tool/smoke_anilist.dart
// ignore_for_file: avoid_print
import 'package:anime_viewer/data/anilist/anilist_client.dart';
import 'package:anime_viewer/data/models/catalog_query.dart';

Future<void> main() async {
  final client = AniListClient();
  try {
    final page = await client.fetchCatalog(
      const CatalogQuery(sort: AnimeSort.trending, includeAdult: true),
      perPage: 5,
    );
    print(
      'catalog: ${page.items.length} items, '
      'hasNextPage=${page.pageInfo.hasNextPage}',
    );
    for (final a in page.items) {
      print(
        '  ${a.id} ${a.title.preferred} score=${a.score10} '
        'adult=${a.isAdult}',
      );
    }

    final search = await client.search('Frieren', perPage: 3);
    print('search: ${search.items.map((a) => a.title.preferred).join(', ')}');

    final d = await client.fetchDetails(16498);
    print(
      'details: ${d.anime.title.preferred}, score=${d.anime.averageScore}, '
      'studios=${d.studios.map((s) => s.name).join(', ')}, '
      'relations=${d.relations.length}, '
      'recommendations=${d.recommendations.length}, '
      'tags=${d.tags.length}, buckets=${d.scoreDistribution.length}',
    );

    final genres = await client.fetchGenres();
    print('genres: ${genres.length} (${genres.take(5).join(', ')}...)');

    try {
      await client.fetchDetails(999999999);
    } on AniListException catch (e) {
      print('not found: $e, isNotFound=${e.isNotFound}');
    }
  } finally {
    client.close();
  }
}
