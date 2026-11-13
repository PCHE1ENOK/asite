import 'dart:convert';

import 'anilist/anilist_client.dart';
import 'cache/app_database.dart';
import 'models/anime.dart';
import 'models/catalog_query.dart';
import 'models/page.dart';

/// Откуда получены данные.
enum DataSource { network, cache }

/// Результат с отметкой источника; [isStale] — кэш старше TTL
/// (отдан, потому что сеть недоступна).
class Cached<T> {
  const Cached(this.data, {required this.source, this.isStale = false});

  final T data;
  final DataSource source;
  final bool isStale;
}

/// Время жизни записей кэша.
class CachePolicy {
  const CachePolicy({
    this.catalog = const Duration(hours: 1),
    this.details = const Duration(hours: 6),
    this.genres = const Duration(days: 7),
    this.seasons = const Duration(hours: 24),
  });

  final Duration catalog;

  /// Карусели сезонов: один запрос на сезон в сутки.
  final Duration seasons;
  final Duration details;
  final Duration genres;
}

/// Доступ к данным AniList с локальным кэшем.
///
/// Свежие записи кэша отдаются без сети. Если запрос в сеть не удался,
/// отдаётся устаревшая запись (если есть), иначе ошибка пробрасывается.
class AnimeRepository {
  AnimeRepository({
    required this._client,
    required this._db,
    this.policy = const CachePolicy(),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AniListClient _client;
  final AppDatabase _db;
  final CachePolicy policy;
  final DateTime Function() _now;

  Future<Cached<Paged<Anime>>> getCatalog(
    CatalogQuery query, {
    int page = 1,
    int perPage = 30,
    bool forceRefresh = false,
    Duration? ttl,
  }) async {
    final key = 'catalog:${query.cacheKey(page, perPage)}';
    final cached = await _readCatalog(key);

    if (!forceRefresh &&
        cached != null &&
        _isFresh(cached.$2, ttl ?? policy.catalog)) {
      return Cached(cached.$1, source: DataSource.cache);
    }

    try {
      final result = await _client.fetchCatalog(
        query,
        page: page,
        perPage: perPage,
      );
      final now = _now();
      await _db.transaction(() async {
        await _db.upsertSummaries({
          for (final a in result.items) a.id: jsonEncode(a.toJson()),
        }, now);
        await _db.putEntry(
          key,
          jsonEncode({
            'ids': [for (final a in result.items) a.id],
            'pageInfo': result.pageInfo.toJson(),
          }),
          now,
        );
      });
      return Cached(result, source: DataSource.network);
    } on AniListException catch (e) {
      if (cached == null || e.isNotFound) rethrow;
      return Cached(cached.$1, source: DataSource.cache, isStale: true);
    }
  }

  /// Самые популярные тайтлы сезона [season] (`WINTER`…`FALL`) года
  /// [year] для карусели каталога. [status] — `RELEASING` (текущий сезон,
  /// только онгоинги) или `NOT_YET_RELEASED` (анонсы следующего); если
  /// AniList вернёт тайтлы с другим статусом, они отбрасываются.
  /// Кэш — сутки.
  Future<Cached<List<Anime>>> getSeason({
    required String season,
    required int year,
    String? status,
    bool includeAdult = true,
    bool forceRefresh = false,
  }) async {
    final r = await getCatalog(
      CatalogQuery(
        season: season,
        seasonYear: year,
        status: status,
        sort: AnimeSort.popularity,
        includeAdult: includeAdult,
      ),
      perPage: 20,
      forceRefresh: forceRefresh,
      ttl: policy.seasons,
    );
    return Cached(
      [
        for (final a in r.data.items)
          if (status == null || a.status == null || a.status == status) a,
      ],
      source: r.source,
      isStale: r.isStale,
    );
  }

  Future<Cached<Paged<Anime>>> search(
    String text, {
    int page = 1,
    int perPage = 30,
  }) => getCatalog(
    CatalogQuery(search: text),
    page: page,
    perPage: perPage,
  );

  Future<Cached<AnimeDetails>> getDetails(
    int id, {
    bool forceRefresh = false,
  }) async {
    final row = await _db.animeById(id);
    final cachedJson = row?.detailsJson;
    final cached = cachedJson == null
        ? null
        : AnimeDetails.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);

    if (!forceRefresh &&
        cached != null &&
        _isFresh(row!.detailsUpdatedAt!, policy.details)) {
      return Cached(cached, source: DataSource.cache);
    }

    try {
      final details = await _client.fetchDetails(id);
      await _db.upsertDetails(
        id,
        summaryJson: jsonEncode(details.anime.toJson()),
        detailsJson: jsonEncode(details.raw),
        now: _now(),
      );
      return Cached(details, source: DataSource.network);
    } on AniListException catch (e) {
      if (cached == null || e.isNotFound) rethrow;
      return Cached(cached, source: DataSource.cache, isStale: true);
    }
  }

  /// Краткие карточки по id: из кэша, недостающие — из сети пачками по 50.
  /// Без сети возвращает то, что есть в кэше.
  Future<Map<int, Anime>> getSummaries(Iterable<int> ids) async {
    final wanted = ids.toSet().toList();
    final result = <int, Anime>{
      for (final row in await _db.animeByIds(wanted))
        row.id: Anime.fromJson(
          jsonDecode(row.summaryJson) as Map<String, dynamic>,
        ),
    };
    final missing = wanted.where((id) => !result.containsKey(id)).toList();
    try {
      for (var i = 0; i < missing.length; i += 50) {
        final chunk = missing.sublist(i, (i + 50).clamp(0, missing.length));
        final items = await _client.fetchByIds(chunk);
        await _db.upsertSummaries({
          for (final a in items) a.id: jsonEncode(a.toJson()),
        }, _now());
        for (final a in items) {
          result[a.id] = a;
        }
      }
    } on AniListException {
      // Без сети — только кэш.
    }
    return result;
  }

  /// Краткая карточка из кэша без обращения к сети.
  Future<Anime?> getCachedSummary(int id) async {
    final row = await _db.animeById(id);
    return row == null
        ? null
        : Anime.fromJson(jsonDecode(row.summaryJson) as Map<String, dynamic>);
  }

  Future<Cached<List<String>>> getGenres({bool forceRefresh = false}) async {
    const key = 'genres';
    final row = await _db.entry(key);
    final cached = row == null
        ? null
        : (jsonDecode(row.payload) as List).cast<String>();

    if (!forceRefresh &&
        cached != null &&
        _isFresh(row!.updatedAt, policy.genres)) {
      return Cached(cached, source: DataSource.cache);
    }

    try {
      final genres = await _client.fetchGenres();
      await _db.putEntry(key, jsonEncode(genres), _now());
      return Cached(genres, source: DataSource.network);
    } on AniListException {
      if (cached == null) rethrow;
      return Cached(cached, source: DataSource.cache, isStale: true);
    }
  }

  /// Чистит кэш от записей старше [maxAge].
  Future<void> prune({Duration maxAge = const Duration(days: 30)}) =>
      _db.pruneOlderThan(_now().subtract(maxAge));

  bool _isFresh(DateTime updatedAt, Duration ttl) =>
      _now().difference(updatedAt) < ttl;

  /// Страница каталога из кэша и время её записи. Если какая-то карточка
  /// пропала из кэша (например, после очистки), страница считается
  /// отсутствующей.
  Future<(Paged<Anime>, DateTime)?> _readCatalog(String key) async {
    final entry = await _db.entry(key);
    if (entry == null) return null;
    final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    final ids = (payload['ids'] as List).cast<int>();
    final rows = await _db.animeByIds(ids);
    if (rows.length != ids.length) return null;
    return (
      Paged(
        items: [
          for (final r in rows)
            Anime.fromJson(jsonDecode(r.summaryJson) as Map<String, dynamic>),
        ],
        pageInfo: PageInfo.fromJson(
          payload['pageInfo'] as Map<String, dynamic>,
        ),
      ),
      entry.updatedAt,
    );
  }
}
