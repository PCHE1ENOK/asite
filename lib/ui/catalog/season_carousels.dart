import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../format.dart';
import '../widgets/poster_carousel.dart';
import 'catalog_filters.dart';

/// Вид карусели сезона.
enum SeasonKind {
  /// Текущий сезон: только онгоинги.
  current('RELEASING'),

  /// Прошедший.
  past(null),

  /// Следующий: анонсы.
  announce('NOT_YET_RELEASED');

  const SeasonKind(this.status);

  /// Фильтр `MediaStatus` для AniList.
  final String? status;
}

/// Карусели сезонов над каталогом (design/screens.md §1.1, решение
/// пользователя): текущий сезон первым (онгоинги), два прошедших по
/// убыванию и «Анонсы» следующего сезона.
class SeasonCarousels extends StatelessWidget {
  const SeasonCarousels({
    super.key,
    required this.onOpenTitle,
    this.now,
    this.count = 4,
  });

  final ValueChanged<Anime> onOpenTitle;
  final DateTime? now;
  final int count;

  /// Показывать карусели над каталогом. Тесты ленты каталога их
  /// выключают: иначе сетка уходит ниже первого экрана.
  static bool enabled = true;

  /// «осеннего» — для «Аниме осеннего сезона».
  static const genitive = {
    'WINTER': 'зимнего',
    'SPRING': 'весеннего',
    'SUMMER': 'летнего',
    'FALL': 'осеннего',
  };

  /// «зиму» — для «Анонсов на зиму 2027 пока нет».
  static const accusative = {
    'WINTER': 'зиму',
    'SPRING': 'весну',
    'SUMMER': 'лето',
    'FALL': 'осень',
  };

  /// Текущий сезон, [count] - 2 прошедших и следующий (анонсы).
  static List<(SeasonOption, SeasonKind)> seasons(
    DateTime now, {
    int count = 4,
  }) {
    final current = SeasonOption.of(now);
    final list = [(current, SeasonKind.current)];
    while (list.length < count - 1) {
      list.add((list.last.$1.previous, SeasonKind.past));
    }
    return [...list, (current.next, SeasonKind.announce)];
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final list = seasons(now ?? DateTime.now(), count: count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 32),
          _SeasonCarousel(
            key: ValueKey(list[i].$1),
            season: list[i].$1,
            kind: list[i].$2,
            onOpenTitle: onOpenTitle,
          ),
        ],
      ],
    );
  }
}

class _SeasonCarousel extends StatefulWidget {
  const _SeasonCarousel({
    super.key,
    required this.season,
    required this.kind,
    required this.onOpenTitle,
  });

  final SeasonOption season;
  final SeasonKind kind;
  final ValueChanged<Anime> onOpenTitle;

  @override
  State<_SeasonCarousel> createState() => _SeasonCarouselState();
}

class _SeasonCarouselState extends State<_SeasonCarousel> {
  List<Anime> _items = const [];
  bool _loading = true;
  bool _error = false;
  AppSettings? _settings;
  bool? _adult;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings != null) return;
    _settings = AppScope.of(context).settings..addListener(_onSettings);
    _adult = _settings!.showAdult;
    _load();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettings);
    super.dispose();
  }

  /// «Показывать 18+» — общий переключатель.
  void _onSettings() {
    if (_settings!.showAdult == _adult) return;
    _adult = _settings!.showAdult;
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final r = await AppScope.of(context).services.anime.getSeason(
        season: widget.season.season,
        year: widget.season.year,
        status: widget.kind.status,
        includeAdult: _adult ?? true,
        forceRefresh: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = r.data;
        _loading = false;
      });
      // Русские названия и оценки Shikimori — как в каталоге.
      AppScope.of(context).services.shiki.prefetch(r.data);
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.season;
    final name = '${Fmt.seasons[s.season]} ${s.year}';
    final announce = widget.kind == SeasonKind.announce;
    // «зиму 2027» — для «Анонсов на зиму 2027 пока нет».
    final accusative = '${SeasonCarousels.accusative[s.season]} ${s.year}';
    return PosterCarousel(
      title: announce
          ? 'Анонсы · ${name.toLowerCase()}'
          : 'Аниме ${SeasonCarousels.genitive[s.season]} сезона',
      subtitle: switch (widget.kind) {
        SeasonKind.current => '$name · сейчас идёт',
        SeasonKind.past => '$name · завершился',
        SeasonKind.announce => 'Ещё не вышли',
      },
      items: _items,
      loading: _loading,
      error: _error,
      onRetry: () => _load(force: true),
      emptyText: announce
          ? 'Анонсов на $accusative пока нет'
          : 'В этом сезоне пока нет онгоингов',
      errorText: announce
          ? 'Не удалось загрузить анонсы'
          : 'Не удалось загрузить онгоинги',
      announce: announce,
      onOpenTitle: widget.onOpenTitle,
    );
  }
}
