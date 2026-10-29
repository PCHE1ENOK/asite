import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/anilist/anilist_client.dart';
import '../data/anime_repository.dart';
import '../data/models/anime.dart';
import '../data/models/catalog_query.dart';

/// Бесконечная лента тайтлов по [CatalogQuery] страницами по 30.
///
/// Ответы на устаревший запрос (фильтры поменялись, пока шла загрузка)
/// отбрасываются. Уже загруженные карточки при ошибке не убираются.
class PagedAnimeController extends ChangeNotifier {
  PagedAnimeController(this._repository, {this.perPage = 30});

  final AnimeRepository _repository;
  final int perPage;

  CatalogQuery? _query;
  final List<Anime> _items = [];
  int _page = 0;
  bool _hasMore = true;
  int? _total;
  bool _loading = false;
  bool _stale = false;
  Object? _error;
  int _generation = 0;
  Timer? _retryTimer;
  DateTime? _rateLimitedUntil;

  CatalogQuery? get query => _query;
  List<Anime> get items => List.unmodifiable(_items);
  bool get hasMore => _hasMore;

  /// Сколько всего результатов (по данным AniList, приблизительно).
  int? get total => _total;
  bool get isLoading => _loading;

  /// Первая страница ещё не пришла.
  bool get isInitialLoading => _loading && _items.isEmpty;

  /// Данные из кэша, потому что сеть недоступна.
  bool get isStale => _stale;
  Object? get error => _error;

  /// AniList попросил подождать; повтор запланирован на это время.
  DateTime? get rateLimitedUntil => _rateLimitedUntil;

  /// Новый запрос: лента сбрасывается и грузится первая страница.
  Future<void> setQuery(CatalogQuery query) {
    _query = query;
    _generation++;
    _retryTimer?.cancel();
    _rateLimitedUntil = null;
    _items.clear();
    _page = 0;
    _hasMore = true;
    _total = null;
    _error = null;
    _stale = false;
    _loading = false;
    return loadMore();
  }

  /// Догружает следующую страницу, если она есть и загрузка не идёт.
  Future<void> loadMore() async {
    final query = _query;
    if (query == null || _loading || !_hasMore) return;
    final generation = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.getCatalog(
        query,
        page: _page + 1,
        perPage: perPage,
      );
      if (generation != _generation) return;
      _page++;
      final seen = {for (final a in _items) a.id};
      _items.addAll(result.data.items.where((a) => seen.add(a.id)));
      _hasMore = result.data.pageInfo.hasNextPage;
      _total = result.data.pageInfo.total ?? _items.length;
      _stale = _stale || result.isStale;
    } on AniListException catch (e) {
      if (generation != _generation) return;
      _error = e;
      if (e.isRateLimited) _scheduleRetry(e.retryAfter);
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Повтор после ошибки.
  Future<void> retry() {
    _retryTimer?.cancel();
    _rateLimitedUntil = null;
    return loadMore();
  }

  void _scheduleRetry(Duration? after) {
    final delay = after ?? const Duration(seconds: 30);
    _rateLimitedUntil = DateTime.now().add(delay);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, retry);
  }

  @override
  void dispose() {
    _generation++;
    _retryTimer?.cancel();
    super.dispose();
  }
}
