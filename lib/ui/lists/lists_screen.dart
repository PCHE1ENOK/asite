import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
import '../../data/favorites/favorites_repository.dart';
import '../widgets/verdict_visuals.dart';
import '../app_scope.dart';
import '../format.dart';
import '../library_index.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../title/title_charts.dart';
import '../widgets/badges.dart';
import '../widgets/cover_image.dart';
import '../widgets/filter_controls.dart';
import '../widgets/poster_card.dart';
import '../widgets/state_views.dart';
import '../widgets/status_visuals.dart';
import '../widgets/status_widgets.dart';
import '../widgets/sync_bar.dart';
import '../widgets/favorite_button.dart';
import '../russian_titles.dart';

/// Фильтр «Заметки» над сеткой (design/screens.md §12).
enum NoteFilter {
  all('Все'),
  withNote('С заметкой'),
  recommend('Советую'),
  rewatch('Стоит пересмотреть'),
  notRecommend('Не советую'),
  none('Без вердикта');

  const NoteFilter(this.label);

  final String label;

  bool matches(TitleNote? n) => switch (this) {
    NoteFilter.all => true,
    NoteFilter.withNote => n != null,
    NoteFilter.recommend => n?.verdict == NoteVerdict.recommend,
    NoteFilter.rewatch => n?.verdict == NoteVerdict.rewatch,
    NoteFilter.notRecommend => n?.verdict == NoteVerdict.notRecommend,
    NoteFilter.none => n != null && n.verdict == NoteVerdict.none,
  };
}

enum ListsSort {
  updated('Недавно обновлённые'),
  score('Моя оценка'),
  title('Название');

  const ListsSort(this.label);

  final String label;
}

/// «Мои списки» (design/screens.md §2): сводка, вкладки по статусам,
/// сетка или список. Работает без входа — данные локальные.
class ListsScreen extends StatefulWidget {
  const ListsScreen({
    super.key,
    required this.onOpenCatalog,
    required this.onOpenTitle,
  });

  final VoidCallback onOpenCatalog;
  final ValueChanged<Anime> onOpenTitle;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen>
    with SingleTickerProviderStateMixin {
  /// Вкладки статусов и после них — «Понравилось».
  late final _tabs = TabController(
    length: statusBarOrder.length + 1,
    vsync: this,
  );
  late FavoritesRepository _favorites;

  bool get _favoritesTab => _tabs.index == statusBarOrder.length;
  late LibraryIndex _library;
  final Map<int, Anime> _summaries = {};
  Set<int> _requested = {};
  ListsSort _sort = ListsSort.updated;
  NoteFilter _noteFilter = NoteFilter.all;

  /// Краткие итоги заметок для вида «список».
  Map<int, TitleNote> _notes = const {};
  StreamSubscription<Map<int, TitleNote>>? _notesSub;
  bool _grid = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _library = AppScope.of(context).library..addListener(_loadSummaries);
    _favorites = AppScope.of(context).services.favorites;
    _favorites.ids.addListener(_loadSummaries);
    _loadSummaries();
    _notesSub = AppScope.of(context).services.notes
        .watchAll()
        .listen((n) => setState(() => _notes = n));
  }

  @override
  void dispose() {
    _library.removeListener(_loadSummaries);
    _favorites.ids.removeListener(_loadSummaries);
    _notesSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// Подгружает карточки AniList для новых тайтлов в списках.
  Future<void> _loadSummaries() async {
    final missing = {
      ..._library.ids,
      ..._favorites.ids.value,
    }.difference(_requested);
    if (missing.isEmpty) return;
    _requested = {..._requested, ...missing};
    final map = await AppScope.of(context).services.anime.getSummaries(missing);
    if (!mounted) return;
    setState(() => _summaries.addAll(map));
    prefetchShikimoriData(context, map.values);
    // Не найденные (нет сети) попробуем при следующем изменении списков.
    _requested = _requested.difference(missing.difference(map.keys.toSet()));
  }

  /// Тайтлы вкладки: статус или «Понравилось» (независимо от статуса).
  List<_Item> _itemsFor(ListStatus? status) {
    final list = status == null
        ? [for (final id in _favorites.ids.value) (id: id, entry: _library[id])]
        : [
            for (final e in _library.entries)
              if (e.status == status ||
                  (status == ListStatus.current &&
                      e.status == ListStatus.repeating))
                (id: e.mediaId, entry: e),
          ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int byTitle(_Item a, _Item b) => (_summaries[a.id]?.title.preferred ?? '')
        .toLowerCase()
        .compareTo((_summaries[b.id]?.title.preferred ?? '').toLowerCase());
    switch (_sort) {
      case ListsSort.updated:
        list.sort(
          (a, b) => (b.entry?.updatedAt ?? epoch).compareTo(
            a.entry?.updatedAt ?? epoch,
          ),
        );
      case ListsSort.score:
        list.sort(
          (a, b) => (b.entry?.score ?? -1).compareTo(a.entry?.score ?? -1),
        );
      case ListsSort.title:
        list.sort(byTitle);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        final compact = width < AppLayout.medium;
        return ListenableBuilder(
          listenable: Listenable.merge([_library, _tabs, _favorites.ids]),
          builder: (context, _) {
            final counts = _library.counts;
            final favorites = _favoritesTab;
            final status = favorites ? null : statusBarOrder[_tabs.index];
            final inTab = _itemsFor(status);
            final entries = [
              for (final e in inTab)
                if (_noteFilter.matches(_notes[e.id])) e,
            ];
            final withSummary = entries.any(
              (e) => _notes[e.id]?.summary.isNotEmpty ?? false,
            );
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    compact ? 16 : 28,
                    gutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Мои списки',
                          style: compact
                              ? AppText.headline
                              : AppText.displayStyle,
                        ),
                        const SizedBox(height: 16),
                        const SyncBar(),
                        if (counts.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: StatusDistributionBar(
                              amounts: counts,
                              caption: (total) =>
                                  '$total ${Fmt.plural(total, 'тайтл', 'тайтла', 'тайтлов')} в списках',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabs: [
                            for (final s in statusBarOrder)
                              Tab(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(Fmt.status(s)),
                                    const SizedBox(width: 6),
                                    _CountPill(count: counts[s] ?? 0),
                                  ],
                                ),
                              ),
                            // Отдельно от статусов: сердце не статус.
                            Tab(
                              child: Container(
                                padding: const EdgeInsets.only(left: 16),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: context.tokens.border,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Symbols.favorite_rounded,
                                      size: 16,
                                      fill: 1,
                                      color: context.tokens.bad,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('Понравилось'),
                                    const SizedBox(width: 6),
                                    _CountPill(
                                      count: _favorites.ids.value.length,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            PillMenu<ListsSort>(
                              label: _sort.label,
                              items: ListsSort.values,
                              value: _sort,
                              itemLabel: (s) => s.label,
                              onSelected: (s) => setState(() => _sort = s),
                            ),
                            const Spacer(),
                            SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(
                                    Symbols.grid_view_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Сетка',
                                ),
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(
                                    Symbols.view_list_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Список',
                                ),
                              ],
                              selected: {_grid},
                              onSelectionChanged: (v) =>
                                  setState(() => _grid = v.first),
                            ),
                          ],
                        ),
                        if (_notes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Заметки:',
                                style: AppText.label.copyWith(
                                  color: context.tokens.fg2,
                                ),
                              ),
                              for (final f in NoteFilter.values)
                                PillButton(
                                  label: f.label,
                                  selected: f == _noteFilter,
                                  onPressed: () =>
                                      setState(() => _noteFilter = f),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (!_library.isLoaded)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (entries.isEmpty && inTab.isNotEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Symbols.filter_alt_off_rounded,
                      text: 'Нет тайтлов с таким вердиктом',
                      actionLabel: 'Показать все',
                      onAction: () =>
                          setState(() => _noteFilter = NoteFilter.all),
                    ),
                  )
                else if (entries.isEmpty && status == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Symbols.favorite_rounded,
                      text: 'Отметьте тайтлы сердцем',
                      hint:
                          'Нажмите ♡ на постере или на карточке тайтла — он '
                          'появится здесь, независимо от статуса',
                      actionLabel: 'Открыть каталог',
                      onAction: widget.onOpenCatalog,
                    ),
                  )
                else if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: statusIcon(status!),
                      text:
                          'Здесь появятся тайтлы, которые вы отметили «${Fmt.status(status)}»',
                      actionLabel: 'Открыть каталог',
                      onAction: widget.onOpenCatalog,
                    ),
                  )
                else if (_grid)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverLayoutBuilder(
                      builder: (context, c) => SliverGrid.builder(
                        gridDelegate: posterGridDelegate(
                          c.crossAxisExtent,
                          extraCaption: withSummary ? PosterCard.noteHeight : 0,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final a = _summaries[entries[i].id];
                          return a == null
                              ? const PosterCardSkeleton()
                              : PosterCard(
                                  anime: a,
                                  note: _notes[entries[i].id],
                                  onTap: () => widget.onOpenTitle(a),
                                );
                        },
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverList.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _ListRow(
                        mediaId: entries[i].id,
                        entry: entries[i].entry,
                        anime: _summaries[entries[i].id],
                        note: _notes[entries[i].id],
                        onTap: widget.onOpenTitle,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        );
      },
    );
  }
}

/// Тайтл во вкладке: id и запись в списках (может не быть у «Понравилось»).
typedef _Item = ({int id, LibraryEntry? entry});

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: AppText.badge.copyWith(color: t.fg2, fontSize: 11),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.mediaId,
    required this.entry,
    required this.anime,
    required this.note,
    required this.onTap,
  });

  final int mediaId;

  /// Запись в списках; у тайтла только с «Понравилось» её нет.
  final LibraryEntry? entry;
  final Anime? anime;
  final TitleNote? note;
  final ValueChanged<Anime> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = anime;
    final total = a?.episodes;
    return InkWell(
      onTap: a == null ? null : () => onTap(a),
      onSecondaryTapUp: (d) =>
          showStatusContextMenu(context, d.globalPosition, mediaId),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 54,
              child: NetworkCover(cover: a?.coverImage, radius: AppRadius.xs),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a != null)
                    AnimeTitleText(
                      a,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    )
                  else
                    Text(
                      'Тайтл #$mediaId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                  Text(
                    note?.summary.isNotEmpty ?? false
                        ? note!.summary.replaceAll('\n', ' ')
                        : entry == null
                        ? 'Понравилось'
                        : 'обновлено ${Fmt.dayMonth(entry!.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: t.fg2),
                  ),
                ],
              ),
            ),
            if (a != null) FavoriteButton(anime: a),
            SizedBox(
              width: 90,
              child: Text(
                entry == null ? '' : '${entry!.progress} / ${total ?? '?'}',
                textAlign: TextAlign.right,
                style: AppText.label.copyWith(fontFeatures: AppText.tabular),
              ),
            ),
            const SizedBox(width: 16),
            if (note case final n?) ...[
              Icon(
                verdictVisual(n.verdict, t).icon,
                size: 18,
                fill: 1,
                color: verdictVisual(n.verdict, t).color,
                semanticLabel: verdictVisual(n.verdict, t).label,
              ),
              const SizedBox(width: 12),
            ],
            if (a != null) AnimeScoreBadge(anime: a),
            const SizedBox(width: 12),
            if (entry case final e?)
              ListStatusDot(status: e.status, size: 22)
            else
              const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }
}
