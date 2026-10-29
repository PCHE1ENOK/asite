/// Сортировка каталога; значения совпадают с enum `MediaSort` в AniList.
enum AnimeSort {
  trending('TRENDING_DESC'),
  popularity('POPULARITY_DESC'),
  score('SCORE_DESC'),
  favourites('FAVOURITES_DESC'),
  newest('START_DATE_DESC'),
  oldest('START_DATE'),
  titleRomaji('TITLE_ROMAJI'),
  searchMatch('SEARCH_MATCH');

  const AnimeSort(this.apiValue);

  final String apiValue;
}

/// Параметры запроса каталога: фильтры, сортировка и поиск.
///
/// Пустые поля не попадают в переменные GraphQL-запроса.
class CatalogQuery {
  const CatalogQuery({
    this.search,
    this.sort,
    this.genres = const [],
    this.excludedGenres = const [],
    this.formats = const [],
    this.status,
    this.season,
    this.seasonYear,
    this.minScore,
    this.includeAdult = false,
  });

  final String? search;

  /// Если не задана: по релевантности при поиске, иначе по популярности.
  final AnimeSort? sort;
  final List<String> genres;
  final List<String> excludedGenres;

  /// Значения `MediaFormat`: `TV`, `MOVIE`, `OVA` и т.д.
  final List<String> formats;

  /// Значение `MediaStatus`.
  final String? status;

  /// Значение `MediaSeason`.
  final String? season;
  final int? seasonYear;

  /// Минимальная средняя оценка по шкале 0–100.
  final int? minScore;
  final bool includeAdult;

  bool get hasSearch => search != null && search!.trim().isNotEmpty;

  /// Переменные для `AniListQueries.catalog`, без пагинации.
  Map<String, dynamic> toVariables() {
    final effectiveSort =
        sort ?? (hasSearch ? AnimeSort.searchMatch : AnimeSort.popularity);
    return {
      'sort': [effectiveSort.apiValue],
      if (hasSearch) 'search': search!.trim(),
      if (genres.isNotEmpty) 'genres': genres,
      if (excludedGenres.isNotEmpty) 'excludedGenres': excludedGenres,
      if (formats.isNotEmpty) 'formats': formats,
      if (status != null) 'status': status,
      if (season != null) 'season': season,
      if (seasonYear != null) 'seasonYear': seasonYear,
      if (minScore != null) 'minScore': minScore,
      if (!includeAdult) 'isAdult': false,
    };
  }

  /// Стабильный ключ для кэширования страниц каталога.
  String cacheKey(int page, int perPage) {
    final vars = toVariables();
    final keys = vars.keys.toList()..sort();
    return [
      for (final k in keys) '$k=${vars[k]}',
      'page=$page',
      'perPage=$perPage',
    ].join('&');
  }
}
