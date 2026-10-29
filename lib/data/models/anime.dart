/// Модели данных тайтлов, нормализованные из ответов AniList.
///
/// Модели умеют сериализоваться обратно в JSON того же формата, что отдаёт
/// AniList (`toJson`), чтобы кэш хранил исходную структуру и читал её тем же
/// парсером, что и сетевой клиент.
library;

/// Названия тайтла на разных языках.
class AnimeTitle {
  const AnimeTitle({this.romaji, this.english, this.native});

  final String? romaji;
  final String? english;
  final String? native;

  /// Предпочтительное название для отображения.
  String get preferred => english ?? romaji ?? native ?? '';

  factory AnimeTitle.fromJson(Map<String, dynamic> json) => AnimeTitle(
    romaji: json['romaji'] as String?,
    english: json['english'] as String?,
    native: json['native'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'romaji': romaji,
    'english': english,
    'native': native,
  };
}

/// Обложка тайтла в нескольких размерах.
class CoverImage {
  const CoverImage({this.medium, this.large, this.extraLarge, this.color});

  final String? medium;
  final String? large;
  final String? extraLarge;

  /// Средний цвет обложки в формате `#rrggbb`.
  final String? color;

  /// Самый крупный доступный размер.
  String? get best => extraLarge ?? large ?? medium;

  factory CoverImage.fromJson(Map<String, dynamic> json) => CoverImage(
    medium: json['medium'] as String?,
    large: json['large'] as String?,
    extraLarge: json['extraLarge'] as String?,
    color: json['color'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'medium': medium,
    'large': large,
    'extraLarge': extraLarge,
    'color': color,
  };
}

/// Дата с необязательными частями, как в AniList `FuzzyDate`.
class FuzzyDate {
  const FuzzyDate({this.year, this.month, this.day});

  final int? year;
  final int? month;
  final int? day;

  bool get isEmpty => year == null && month == null && day == null;

  static FuzzyDate? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final date = FuzzyDate(
      year: json['year'] as int?,
      month: json['month'] as int?,
      day: json['day'] as int?,
    );
    return date.isEmpty ? null : date;
  }

  Map<String, dynamic> toJson() => {'year': year, 'month': month, 'day': day};

  @override
  String toString() => [
    year?.toString(),
    month?.toString().padLeft(2, '0'),
    day?.toString().padLeft(2, '0'),
  ].whereType<String>().join('-');
}

/// Краткая информация о тайтле для каталога и поиска.
class Anime {
  const Anime({
    required this.id,
    required this.title,
    this.idMal,
    this.coverImage = const CoverImage(),
    this.bannerImage,
    this.format,
    this.status,
    this.episodes,
    this.duration,
    this.season,
    this.seasonYear,
    this.averageScore,
    this.meanScore,
    this.popularity,
    this.favourites,
    this.genres = const [],
    this.isAdult = false,
  });

  final int id;
  final int? idMal;
  final AnimeTitle title;
  final CoverImage coverImage;
  final String? bannerImage;

  /// `TV`, `MOVIE`, `OVA`, `ONA`, `SPECIAL`, `TV_SHORT`, `MUSIC`.
  final String? format;

  /// `FINISHED`, `RELEASING`, `NOT_YET_RELEASED`, `CANCELLED`, `HIATUS`.
  final String? status;
  final int? episodes;

  /// Длительность эпизода в минутах.
  final int? duration;

  /// `WINTER`, `SPRING`, `SUMMER`, `FALL`.
  final String? season;
  final int? seasonYear;

  /// Взвешенная оценка AniList, 0–100.
  final int? averageScore;

  /// Средняя оценка пользователей AniList, 0–100.
  final int? meanScore;
  final int? popularity;
  final int? favourites;
  final List<String> genres;
  final bool isAdult;

  /// Оценка для отображения по шкале 0–10 (например, `8.4`).
  double? get score10 {
    final s = averageScore ?? meanScore;
    return s == null ? null : s / 10;
  }

  factory Anime.fromJson(Map<String, dynamic> json) => Anime(
    id: json['id'] as int,
    idMal: json['idMal'] as int?,
    title: AnimeTitle.fromJson(_map(json['title'])),
    coverImage: CoverImage.fromJson(_map(json['coverImage'])),
    bannerImage: json['bannerImage'] as String?,
    format: json['format'] as String?,
    status: json['status'] as String?,
    episodes: json['episodes'] as int?,
    duration: json['duration'] as int?,
    season: json['season'] as String?,
    seasonYear: json['seasonYear'] as int?,
    averageScore: json['averageScore'] as int?,
    meanScore: json['meanScore'] as int?,
    popularity: json['popularity'] as int?,
    favourites: json['favourites'] as int?,
    genres: _strings(json['genres']),
    isAdult: json['isAdult'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'idMal': idMal,
    'title': title.toJson(),
    'coverImage': coverImage.toJson(),
    'bannerImage': bannerImage,
    'format': format,
    'status': status,
    'episodes': episodes,
    'duration': duration,
    'season': season,
    'seasonYear': seasonYear,
    'averageScore': averageScore,
    'meanScore': meanScore,
    'popularity': popularity,
    'favourites': favourites,
    'genres': genres,
    'isAdult': isAdult,
  };
}

/// Распределение оценок пользователей (шаг 10 по шкале 0–100).
class ScoreBucket {
  const ScoreBucket({required this.score, required this.amount});

  final int score;
  final int amount;

  factory ScoreBucket.fromJson(Map<String, dynamic> json) =>
      ScoreBucket(score: json['score'] as int, amount: json['amount'] as int);

  Map<String, dynamic> toJson() => {'score': score, 'amount': amount};
}

/// Сколько пользователей AniList держат тайтл в каждом статусе.
class StatusBucket {
  const StatusBucket({required this.status, required this.amount});

  /// Значение `MediaListStatus`: `CURRENT`, `PLANNING` и т.д.
  final String status;
  final int amount;
}

/// Место тайтла в рейтинге AniList.
class Ranking {
  const Ranking({
    required this.rank,
    required this.type,
    required this.allTime,
    this.season,
    this.year,
    this.context,
  });

  final int rank;

  /// `RATED` или `POPULAR`.
  final String type;
  final bool allTime;
  final String? season;
  final int? year;
  final String? context;
}

/// Эпизод со стриминговой площадки, указанной на AniList (только название
/// и превью; видео приложение отсюда не берёт).
class StreamingEpisode {
  const StreamingEpisode({required this.title, this.thumbnail});

  final String title;
  final String? thumbnail;

  /// Номер серии из названия вида «Episode 3 - Title», если он есть.
  int? get number {
    final m = RegExp(
      r'(?:Episode|Эпизод|Серия)\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Название без префикса «Episode N - ».
  String get cleanTitle => title
      .replaceFirst(
        RegExp(
          r'^(?:Episode|Эпизод|Серия)\s+\d+\s*[-–:]\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

/// Будущий выход серии.
class AiringEpisode {
  const AiringEpisode({required this.episode, required this.airingAt});

  final int episode;
  final DateTime airingAt;
}

/// Студия-производитель.
class Studio {
  const Studio({required this.id, required this.name, this.isMain = false});

  final int id;
  final String name;
  final bool isMain;
}

/// Связанный тайтл (сиквел, приквел и т.п.).
class RelatedAnime {
  const RelatedAnime({required this.relationType, required this.anime});

  /// `SEQUEL`, `PREQUEL`, `SIDE_STORY`, `ADAPTATION` и т.д.
  final String relationType;
  final Anime anime;
}

/// Тег с рейтингом релевантности.
class AnimeTag {
  const AnimeTag({required this.name, this.rank, this.isSpoiler = false});

  final String name;
  final int? rank;
  final bool isSpoiler;
}

/// Трейлер; для YouTube `site == 'youtube'`.
class Trailer {
  const Trailer({required this.id, required this.site, this.thumbnail});

  final String id;
  final String site;
  final String? thumbnail;
}

/// Ближайший выходящий эпизод.
class NextAiringEpisode {
  const NextAiringEpisode({required this.episode, required this.airingAt});

  final int episode;
  final DateTime airingAt;
}

/// Полная карточка тайтла.
class AnimeDetails {
  const AnimeDetails({
    required this.anime,
    this.description,
    this.startDate,
    this.endDate,
    this.synonyms = const [],
    this.source,
    this.countryOfOrigin,
    this.studios = const [],
    this.tags = const [],
    this.relations = const [],
    this.recommendations = const [],
    this.scoreDistribution = const [],
    this.statusDistribution = const [],
    this.rankings = const [],
    this.streamingEpisodes = const [],
    this.airingSchedule = const [],
    this.trailer,
    this.nextAiringEpisode,
    this.siteUrl,
    this.raw = const {},
  });

  final Anime anime;

  /// Описание в HTML-разметке AniList.
  final String? description;
  final FuzzyDate? startDate;
  final FuzzyDate? endDate;
  final List<String> synonyms;
  final String? source;
  final String? countryOfOrigin;
  final List<Studio> studios;
  final List<AnimeTag> tags;
  final List<RelatedAnime> relations;
  final List<Anime> recommendations;
  final List<ScoreBucket> scoreDistribution;
  final List<StatusBucket> statusDistribution;
  final List<Ranking> rankings;
  final List<StreamingEpisode> streamingEpisodes;

  /// Ещё не вышедшие серии по возрастанию номера.
  final List<AiringEpisode> airingSchedule;
  final Trailer? trailer;
  final NextAiringEpisode? nextAiringEpisode;
  final String? siteUrl;

  /// Исходный объект `Media` из ответа AniList; хранится в кэше.
  final Map<String, dynamic> raw;

  int get id => anime.id;

  /// Лучшее место по рейтингу: сначала за сезон, потом за всё время.
  Ranking? get bestRatedRanking {
    final rated = rankings.where((r) => r.type == 'RATED').toList();
    return rated.where((r) => r.season != null).firstOrNull ??
        rated.where((r) => r.allTime).firstOrNull;
  }

  /// Описание без HTML-тегов.
  String? get plainDescription => description
      ?.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  /// Принимает объект `Media` из ответа запроса деталей.
  factory AnimeDetails.fromJson(Map<String, dynamic> json) {
    final trailer = json['trailer'] as Map<String, dynamic>?;
    final next = json['nextAiringEpisode'] as Map<String, dynamic>?;
    return AnimeDetails(
      anime: Anime.fromJson(json),
      description: json['description'] as String?,
      startDate: FuzzyDate.fromJson(json['startDate'] as Map<String, dynamic>?),
      endDate: FuzzyDate.fromJson(json['endDate'] as Map<String, dynamic>?),
      synonyms: _strings(json['synonyms']),
      source: json['source'] as String?,
      countryOfOrigin: json['countryOfOrigin'] as String?,
      studios: [
        for (final edge in _list(_map(json['studios'])['edges']))
          Studio(
            id: _map(edge['node'])['id'] as int,
            name: _map(edge['node'])['name'] as String,
            isMain: edge['isMain'] as bool? ?? false,
          ),
      ],
      tags: [
        for (final t in _list(json['tags']))
          AnimeTag(
            name: t['name'] as String,
            rank: t['rank'] as int?,
            isSpoiler:
                (t['isMediaSpoiler'] as bool? ?? false) ||
                (t['isGeneralSpoiler'] as bool? ?? false),
          ),
      ],
      relations: [
        for (final edge in _list(_map(json['relations'])['edges']))
          if (_map(edge['node'])['type'] == 'ANIME')
            RelatedAnime(
              relationType: edge['relationType'] as String? ?? 'OTHER',
              anime: Anime.fromJson(_map(edge['node'])),
            ),
      ],
      recommendations: [
        for (final node in _list(_map(json['recommendations'])['nodes']))
          if (node['mediaRecommendation'] != null)
            Anime.fromJson(_map(node['mediaRecommendation'])),
      ],
      scoreDistribution: [
        for (final b in _list(_map(json['stats'])['scoreDistribution']))
          ScoreBucket.fromJson(b),
      ],
      statusDistribution: [
        for (final b in _list(_map(json['stats'])['statusDistribution']))
          if (b['status'] is String && b['amount'] is int)
            StatusBucket(
              status: b['status'] as String,
              amount: b['amount'] as int,
            ),
      ],
      rankings: [
        for (final r in _list(json['rankings']))
          if (r['rank'] is int && r['type'] is String)
            Ranking(
              rank: r['rank'] as int,
              type: r['type'] as String,
              allTime: r['allTime'] as bool? ?? false,
              season: r['season'] as String?,
              year: r['year'] as int?,
              context: r['context'] as String?,
            ),
      ],
      streamingEpisodes: [
        for (final e in _list(json['streamingEpisodes']))
          if (e['title'] is String)
            StreamingEpisode(
              title: e['title'] as String,
              thumbnail: e['thumbnail'] as String?,
            ),
      ],
      airingSchedule: [
        for (final n in _list(_map(json['airingSchedule'])['nodes']))
          if (n['episode'] is int && n['airingAt'] is int)
            AiringEpisode(
              episode: n['episode'] as int,
              airingAt: _epoch(n['airingAt'] as int),
            ),
      ]..sort((a, b) => a.episode.compareTo(b.episode)),
      trailer: trailer == null || trailer['id'] == null
          ? null
          : Trailer(
              id: trailer['id'] as String,
              site: trailer['site'] as String? ?? '',
              thumbnail: trailer['thumbnail'] as String?,
            ),
      nextAiringEpisode: next == null
          ? null
          : NextAiringEpisode(
              episode: next['episode'] as int,
              airingAt: _epoch(next['airingAt'] as int),
            ),
      siteUrl: json['siteUrl'] as String?,
      raw: json,
    );
  }
}

DateTime _epoch(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _list(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];
