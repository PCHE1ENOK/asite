import 'package:anime_viewer/ui/catalog/catalog_filters.dart';
import 'package:anime_viewer/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact numbers', () {
    expect(Fmt.compact(950000), '950 тыс.');
    expect(Fmt.compact(1200000), '1,2 млн');
    expect(Fmt.compact(12000000), '12 млн');
    expect(Fmt.compact(950), '950');
    expect(Fmt.thousands(24310), '24 310');
  });

  test('plural', () {
    expect(Fmt.plural(1, 'а', 'б', 'в'), 'а');
    expect(Fmt.plural(3, 'а', 'б', 'в'), 'б');
    expect(Fmt.plural(11, 'а', 'б', 'в'), 'в');
    expect(Fmt.plural(22, 'а', 'б', 'в'), 'б');
  });

  test('AniList seasons: December is next year winter', () {
    expect(
      SeasonOption.of(DateTime(2026, 10, 29)),
      const SeasonOption('FALL', 2026),
    );
    expect(
      SeasonOption.of(DateTime(2026, 12, 5)),
      const SeasonOption('WINTER', 2027),
    );
    expect(
      SeasonOption.of(DateTime(2027, 2, 1)),
      const SeasonOption('WINTER', 2027),
    );
    expect(
      SeasonOption.of(DateTime(2027, 3, 1)),
      const SeasonOption('SPRING', 2027),
    );
    final recent = SeasonOption.recent(DateTime(2026, 10, 29), count: 3);
    expect(recent, const [
      SeasonOption('WINTER', 2027),
      SeasonOption('FALL', 2026),
      SeasonOption('SUMMER', 2026),
    ]);
  });

  test('filters build the AniList query', () {
    final f = const CatalogFilters().copyWith(
      season: () => const SeasonOption('FALL', 2026),
      genres: {'Drama', 'Action'},
      formats: {'MOVIE', 'TV'},
      status: () => 'RELEASING',
    );
    expect(f.hasFilters, isTrue);
    expect(f.toQuery(includeAdult: false).toVariables(), {
      'sort': ['POPULARITY_DESC'],
      'genres': ['Action', 'Drama'],
      'formats': ['TV', 'MOVIE'],
      'status': 'RELEASING',
      'season': 'FALL',
      'seasonYear': 2026,
      'isAdult': false,
    });
    expect(f.cleared().hasFilters, isFalse);
  });
}
