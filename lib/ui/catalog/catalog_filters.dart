import '../../data/models/catalog_query.dart';

/// Сезон AniList с годом.
class SeasonOption {
  const SeasonOption(this.season, this.year);

  final String season;
  final int year;

  static const order = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];

  /// Сезон, в который попадает [date]: зима — декабрь–февраль (декабрь
  /// относится к зиме следующего года, как на AniList).
  factory SeasonOption.of(DateTime date) {
    final m = date.month;
    if (m == 12) return SeasonOption('WINTER', date.year + 1);
    return SeasonOption(order[(m ~/ 3) % 4], date.year);
  }

  SeasonOption get previous {
    final i = order.indexOf(season);
    return i == 0
        ? SeasonOption('FALL', year - 1)
        : SeasonOption(order[i - 1], year);
  }

  SeasonOption get next {
    final i = order.indexOf(season);
    return i == 3
        ? SeasonOption('WINTER', year + 1)
        : SeasonOption(order[i + 1], year);
  }

  /// Следующий сезон, текущий и [count] - 2 прошлых.
  static List<SeasonOption> recent(DateTime now, {int count = 8}) {
    final current = SeasonOption.of(now);
    final list = [current.next, current];
    while (list.length < count) {
      list.add(list.last.previous);
    }
    return list;
  }

  @override
  bool operator ==(Object other) =>
      other is SeasonOption && other.season == season && other.year == year;

  @override
  int get hashCode => Object.hash(season, year);
}

/// Состояние фильтров каталога. 18+ берётся из общих настроек.
class CatalogFilters {
  const CatalogFilters({
    this.sort = AnimeSort.popularity,
    this.season,
    this.genres = const {},
    this.formats = const {},
    this.status,
    this.hideMine = false,
  });

  final AnimeSort sort;
  final SeasonOption? season;
  final Set<String> genres;
  final Set<String> formats;
  final String? status;

  /// «Скрыть из моих списков».
  final bool hideMine;

  static const sorts = [
    AnimeSort.popularity,
    AnimeSort.score,
    AnimeSort.trending,
    AnimeSort.newest,
    AnimeSort.titleRomaji,
  ];

  static const formatOptions = ['TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'];
  static const statusOptions = ['RELEASING', 'FINISHED', 'NOT_YET_RELEASED'];

  static String sortLabel(AnimeSort s) => switch (s) {
    AnimeSort.popularity => 'Популярность',
    AnimeSort.score => 'Рейтинг AniList',
    AnimeSort.trending => 'В тренде',
    AnimeSort.newest => 'Новые',
    AnimeSort.titleRomaji => 'По алфавиту',
    AnimeSort.favourites => 'Избранное',
    AnimeSort.oldest => 'Старые',
    AnimeSort.searchMatch => 'По совпадению',
  };

  /// Выбран ли хоть один фильтр (кроме сортировки).
  bool get hasFilters =>
      season != null ||
      genres.isNotEmpty ||
      formats.isNotEmpty ||
      status != null ||
      hideMine;

  CatalogFilters copyWith({
    AnimeSort? sort,
    SeasonOption? Function()? season,
    Set<String>? genres,
    Set<String>? formats,
    String? Function()? status,
    bool? hideMine,
  }) => CatalogFilters(
    sort: sort ?? this.sort,
    season: season == null ? this.season : season(),
    genres: genres ?? this.genres,
    formats: formats ?? this.formats,
    status: status == null ? this.status : status(),
    hideMine: hideMine ?? this.hideMine,
  );

  CatalogFilters cleared() => CatalogFilters(sort: sort);

  /// [myIds] — тайтлы из моих списков, исключаются при [hideMine].
  CatalogQuery toQuery({
    required bool includeAdult,
    Set<int> myIds = const {},
  }) => CatalogQuery(
    sort: sort,
    season: season?.season,
    seasonYear: season?.year,
    genres: genres.toList()..sort(),
    formats: [
      for (final f in formatOptions)
        if (formats.contains(f)) f,
    ],
    status: status,
    includeAdult: includeAdult,
    excludeIds: hideMine ? myIds.toList() : const [],
  );
}
