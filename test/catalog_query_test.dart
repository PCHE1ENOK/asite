import 'package:anime_viewer/data/models/catalog_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default query sorts by popularity and hides adult titles', () {
    expect(const CatalogQuery().toVariables(), {
      'sort': ['POPULARITY_DESC'],
      'isAdult': false,
    });
  });

  test('blank search is ignored', () {
    expect(
      const CatalogQuery(search: '   ').toVariables().containsKey('search'),
      isFalse,
    );
  });

  test('explicit sort wins over search relevance', () {
    final vars = const CatalogQuery(
      search: 'x',
      sort: AnimeSort.score,
    ).toVariables();
    expect(vars['sort'], ['SCORE_DESC']);
  });

  test('cache key is stable and depends on page', () {
    const a = CatalogQuery(genres: ['Drama'], seasonYear: 2020);
    const b = CatalogQuery(seasonYear: 2020, genres: ['Drama']);
    expect(a.cacheKey(1, 30), b.cacheKey(1, 30));
    expect(a.cacheKey(1, 30), isNot(a.cacheKey(2, 30)));
  });
}
