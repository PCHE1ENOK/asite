import 'package:anime_viewer/ui/catalog/catalog_filters.dart';
import 'package:anime_viewer/ui/catalog/season_carousels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String s(SeasonOption o) => '${o.season} ${o.year}';

  test('current season by device date, month boundaries', () {
    final cases = {
      DateTime(2026, 1, 1): 'WINTER 2026',
      DateTime(2026, 2, 28, 23, 59): 'WINTER 2026',
      DateTime(2026, 3, 1): 'SPRING 2026',
      DateTime(2026, 5, 31, 23, 59): 'SPRING 2026',
      DateTime(2026, 6, 1): 'SUMMER 2026',
      DateTime(2026, 8, 31, 23, 59): 'SUMMER 2026',
      DateTime(2026, 9, 1): 'FALL 2026',
      DateTime(2026, 11, 30, 23, 59): 'FALL 2026',
      // Декабрь — зима следующего года, как на AniList.
      DateTime(2026, 12, 1): 'WINTER 2027',
      DateTime(2026, 12, 31, 23, 59): 'WINTER 2027',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(s(SeasonOption.of(key)), value, reason: '$key');
    }
  });

  test('carousels: current season first, then past ones', () {
    expect(SeasonCarousels.seasons(DateTime(2026, 11, 13)).map(s), [
      'FALL 2026',
      'SUMMER 2026',
      'SPRING 2026',
      'WINTER 2026',
    ]);
    expect(SeasonCarousels.seasons(DateTime(2026, 12, 5)).map(s), [
      'WINTER 2027',
      'FALL 2026',
      'SUMMER 2026',
      'SPRING 2026',
    ]);
    expect(
      SeasonCarousels.seasons(DateTime(2027, 2, 1)).first,
      isA<SeasonOption>(),
    );
    expect(s(SeasonCarousels.seasons(DateTime(2027, 2, 1))[1]), 'FALL 2026');
  });
}
