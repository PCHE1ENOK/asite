import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/anilist/anilist_client.dart';
import '../../data/models/anime.dart';
import '../../data/models/catalog_query.dart';
import '../app_scope.dart';
import '../format.dart';
import '../library_index.dart';
import '../paged_anime_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/filter_controls.dart';
import '../widgets/poster_grid.dart';
import 'catalog_filters.dart';

/// Каталог: фильтры, сортировка и сетка постеров (design/screens.md §1).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.onOpenTitle,
    required this.onOpenSearch,
    this.now,
  });

  final ValueChanged<Anime> onOpenTitle;
  final VoidCallback onOpenSearch;

  /// Текущее время для списка сезонов (в тестах фиксируется).
  final DateTime? now;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late PagedAnimeController _feed;
  late AppSettings _settings;
  late LibraryIndex _library;
  Set<int> _lastIds = const {};
  CatalogFilters _filters = const CatalogFilters();
  List<String> _genres = const [];
  bool _initialized = false;
  bool _lastAdult = true;
  DateTime? _shownRateLimit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final scope = AppScope.of(context);
    _settings = scope.settings..addListener(_onSettings);
    _lastAdult = _settings.showAdult;
    _library = scope.library..addListener(_onLibrary);
    _lastIds = _library.ids;
    _feed = PagedAnimeController(scope.services.anime)..addListener(_onFeed);
    _reload();
    _loadGenres();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _library.removeListener(_onLibrary);
    _feed.dispose();
    super.dispose();
  }

  Future<void> _loadGenres() async {
    try {
      final r = await AppScope.of(context).services.anime.getGenres();
      if (mounted) setState(() => _genres = r.data);
    } on AniListException {
      // Без списка жанров фильтр просто не показывается.
    }
  }

  void _onSettings() {
    if (_settings.showAdult != _lastAdult) {
      _lastAdult = _settings.showAdult;
      _reload();
    }
  }

  void _onLibrary() {
    final ids = _library.ids;
    if (_filters.hideMine && !setEquals(ids, _lastIds)) {
      _lastIds = ids;
      _reload();
    } else {
      _lastIds = ids;
    }
  }

  void _onFeed() {
    final until = _feed.rateLimitedUntil;
    if (until != null && until != _shownRateLimit && mounted) {
      _shownRateLimit = until;
      final seconds = until.difference(DateTime.now()).inSeconds.clamp(1, 999);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('AniList просит подождать. Повторим через $seconds с'),
        ),
      );
    }
  }

  void _reload() => _feed.setQuery(
    _filters.toQuery(includeAdult: _settings.showAdult, myIds: _library.ids),
  );

  void _update(CatalogFilters filters) {
    setState(() => _filters = filters);
    _reload();
  }

  void _resetFilters() {
    setState(() => _filters = _filters.cleared());
    if (!_settings.showAdult) {
      _settings.setShowAdult(true); // перезагрузит через _onSettings
    } else {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        // Шапка и фильтры не зависят от ленты: при подгрузке страниц
        // пересобирается только сетка (те же экземпляры шапки).
        final header = [
          SliverToBoxAdapter(child: _header(context, width, gutter)),
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: _settings,
              builder: (context, _) => _filterBar(context, width, gutter),
            ),
          ),
        ];
        return ListenableBuilder(
          listenable: _feed,
          builder: (context, _) => PosterGrid(
            controller: _feed,
            gutter: gutter,
            onOpenTitle: widget.onOpenTitle,
            header: header,
            emptyText: 'Ничего не нашлось по этим фильтрам',
            emptyActionLabel: 'Сбросить фильтры',
            onEmptyAction: _resetFilters,
            errorText: 'Не удалось загрузить каталог. Проверьте подключение',
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, double width, double gutter) {
    final t = context.tokens;
    final compact = width < AppLayout.medium;
    final title = Text(
      'Каталог',
      style: compact ? AppText.headline : AppText.displayStyle,
    );
    final search = _SearchLauncher(onTap: widget.onOpenSearch);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, compact ? 16 : 28, gutter, 16),
      child: compact
          ? Row(
              children: [
                Expanded(child: title),
                IconButton(
                  tooltip: 'Поиск',
                  onPressed: widget.onOpenSearch,
                  icon: Icon(Symbols.search_rounded, color: t.fg),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: search,
                ),
              ],
            ),
    );
  }

  Widget _filterBar(BuildContext context, double width, double gutter) {
    final f = _filters;
    final seasons = SeasonOption.recent(widget.now ?? DateTime.now());
    final genres = _settings.showAdult
        ? _genres
        : _genres.where((g) => g != 'Hentai').toList();

    final controls = <Widget>[
      PillMenu<SeasonOption?>(
        label: f.season == null
            ? 'Сезон: любой'
            : Fmt.season(f.season!.season, f.season!.year)!,
        selected: f.season != null,
        items: [null, ...seasons],
        value: f.season,
        itemLabel: (s) => s == null ? 'Любой' : Fmt.season(s.season, s.year)!,
        onSelected: (s) => _update(f.copyWith(season: () => s)),
      ),
      if (genres.isNotEmpty)
        PillButton(
          label: f.genres.isEmpty ? 'Жанры' : 'Жанры · ${f.genres.length}',
          selected: f.genres.isNotEmpty,
          trailingIcon: Symbols.expand_more_rounded,
          onPressed: () => _pickGenres(genres),
        ),
      for (final format in CatalogFilters.formatOptions)
        PillButton(
          label: Fmt.formats[format]!,
          selected: f.formats.contains(format),
          onPressed: () {
            final next = {...f.formats};
            if (!next.remove(format)) next.add(format);
            _update(f.copyWith(formats: next));
          },
        ),
      PillMenu<String?>(
        label: f.status == null
            ? 'Статус выхода'
            : Fmt.releaseStatuses[f.status]!,
        selected: f.status != null,
        items: [null, ...CatalogFilters.statusOptions],
        value: f.status,
        itemLabel: (s) => s == null ? 'Любой' : Fmt.releaseStatuses[s]!,
        onSelected: (s) => _update(f.copyWith(status: () => s)),
      ),
      PillButton(
        label: 'Скрыть из моих списков',
        selected: f.hideMine,
        icon: f.hideMine ? Symbols.check_rounded : null,
        onPressed: () => _update(f.copyWith(hideMine: !f.hideMine)),
      ),
      PillButton(
        label: 'Показывать 18+',
        selected: _settings.showAdult,
        icon: _settings.showAdult
            ? Symbols.check_rounded
            : Symbols.visibility_off_rounded,
        onPressed: () => _settings.setShowAdult(!_settings.showAdult),
      ),
      if (f.hasFilters || !_settings.showAdult)
        TextButton.icon(
          onPressed: _resetFilters,
          icon: const Icon(Symbols.close_rounded, size: 18),
          label: const Text('Сбросить'),
        ),
    ];

    final sort = PillMenu<AnimeSort>(
      label: CatalogFilters.sortLabel(f.sort),
      items: CatalogFilters.sorts,
      value: f.sort,
      itemLabel: CatalogFilters.sortLabel,
      onSelected: (s) => _update(f.copyWith(sort: s)),
    );

    final sortRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Сортировка',
          style: AppText.caption.copyWith(color: context.tokens.fg2),
        ),
        const SizedBox(width: 8),
        sort,
      ],
    );

    if (width < AppLayout.expanded) {
      // Узкий экран: одна строка с горизонтальной прокруткой.
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Row(
            children: [
              for (final c in [sortRow, ...controls]) ...[
                c,
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: controls,
            ),
          ),
          const SizedBox(width: 16),
          sortRow,
        ],
      ),
    );
  }

  Future<void> _pickGenres(List<String> genres) async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (context) =>
          _GenreDialog(genres: genres, selected: _filters.genres),
    );
    if (picked != null) _update(_filters.copyWith(genres: picked));
  }
}

class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: t.borderStrong),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Symbols.search_rounded, size: 20, color: t.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Поиск по названию',
                  style: AppText.body.copyWith(color: t.fg3),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'Ctrl K',
                  style: AppText.caption.copyWith(color: t.fg3, fontSize: 11),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreDialog extends StatefulWidget {
  const _GenreDialog({required this.genres, required this.selected});

  final List<String> genres;
  final Set<String> selected;

  @override
  State<_GenreDialog> createState() => _GenreDialogState();
}

class _GenreDialogState extends State<_GenreDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.tokens.surface2,
      title: Text('Жанры', style: AppText.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in widget.genres)
                PillButton(
                  label: Fmt.genre(g),
                  selected: _selected.contains(g),
                  onPressed: () => setState(() {
                    if (!_selected.remove(g)) _selected.add(g);
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('Очистить'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
