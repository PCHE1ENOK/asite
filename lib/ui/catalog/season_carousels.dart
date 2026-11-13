import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../format.dart';
import '../widgets/poster_carousel.dart';
import 'catalog_filters.dart';

/// Карусели сезонов над каталогом (design/screens.md §1.1): текущий сезон
/// первым (только онгоинги), дальше три прошедших по убыванию.
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

  /// Текущий сезон и [count] - 1 прошедших.
  static List<SeasonOption> seasons(DateTime now, {int count = 4}) {
    final list = [SeasonOption.of(now)];
    while (list.length < count) {
      list.add(list.last.previous);
    }
    return list;
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
            key: ValueKey(list[i]),
            season: list[i],
            airing: i == 0,
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
    required this.airing,
    required this.onOpenTitle,
  });

  final SeasonOption season;
  final bool airing;
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
        airing: widget.airing,
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
    return PosterCarousel(
      title: 'Аниме ${SeasonCarousels.genitive[s.season]} сезона',
      subtitle:
          '${Fmt.seasons[s.season]} ${s.year} · '
          '${widget.airing ? 'сейчас идёт' : 'завершился'}',
      items: _items,
      loading: _loading,
      error: _error,
      onRetry: () => _load(force: true),
      emptyText: 'В этом сезоне пока нет онгоингов',
      errorText: 'Не удалось загрузить онгоинги',
      onOpenTitle: widget.onOpenTitle,
    );
  }
}
