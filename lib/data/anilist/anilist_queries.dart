/// GraphQL-запросы к AniList API v2.
abstract final class AniListQueries {
  /// Поля краткой карточки, общие для каталога, поиска и связей.
  static const _mediaSummary = '''
fragment MediaSummary on Media {
  id
  idMal
  title { romaji english native }
  coverImage { medium large extraLarge color }
  bannerImage
  format
  status
  episodes
  duration
  season
  seasonYear
  averageScore
  meanScore
  popularity
  favourites
  genres
  isAdult
}
''';

  /// Каталог с фильтрами, сортировкой и необязательным поиском.
  static const catalog = '''
query Catalog(
  \$page: Int, \$perPage: Int, \$sort: [MediaSort], \$search: String,
  \$genres: [String], \$excludedGenres: [String], \$formats: [MediaFormat],
  \$status: MediaStatus, \$season: MediaSeason, \$seasonYear: Int,
  \$minScore: Int, \$isAdult: Boolean
) {
  Page(page: \$page, perPage: \$perPage) {
    pageInfo { total perPage currentPage lastPage hasNextPage }
    media(
      type: ANIME, sort: \$sort, search: \$search,
      genre_in: \$genres, genre_not_in: \$excludedGenres, format_in: \$formats,
      status: \$status, season: \$season, seasonYear: \$seasonYear,
      averageScore_greater: \$minScore, isAdult: \$isAdult
    ) {
      ...MediaSummary
    }
  }
}
$_mediaSummary''';

  /// Полная карточка тайтла.
  static const details = '''
query Details(\$id: Int) {
  Media(id: \$id, type: ANIME) {
    ...MediaSummary
    description(asHtml: false)
    startDate { year month day }
    endDate { year month day }
    synonyms
    source
    countryOfOrigin
    siteUrl
    trailer { id site thumbnail }
    nextAiringEpisode { episode airingAt }
    studios(isMain: true) { edges { isMain node { id name } } }
    tags { name rank isMediaSpoiler isGeneralSpoiler }
    stats {
      scoreDistribution { score amount }
      statusDistribution { status amount }
    }
    rankings { rank type allTime season year context }
    streamingEpisodes { title thumbnail }
    airingSchedule(notYetAired: true, perPage: 25) {
      nodes { episode airingAt }
    }
    relations {
      edges {
        relationType(version: 2)
        node { type ...MediaSummary }
      }
    }
    recommendations(perPage: 12, sort: [RATING_DESC]) {
      nodes { mediaRecommendation { ...MediaSummary } }
    }
  }
}
$_mediaSummary''';

  /// Список всех жанров для фильтров.
  static const genres = '''
query Genres {
  GenreCollection
}
''';
}
