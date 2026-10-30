import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
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
  late final _tabs = TabController(length: statusBarOrder.length, vsync: this);
  late LibraryIndex _library;
  final Map<int, Anime> _summaries = {};
  Set<int> _requested = {};
  ListsSort _sort = ListsSort.updated;

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
    _loadSummaries();
    _notesSub = AppScope.of(context).services.notes
        .watchAll()
        .listen((n) => setState(() => _notes = n));
  }

  @override
  void dispose() {
    _library.removeListener(_loadSummaries);
    _notesSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// Подгружает карточки AniList для новых тайтлов в списках.
  Future<void> _loadSummaries() async {
    final missing = _library.ids.difference(_requested);
    if (missing.isEmpty) return;
    _requested = {..._requested, ...missing};
    final map = await AppScope.of(context).services.anime.getSummaries(missing);
    if (!mounted) return;
    setState(() => _summaries.addAll(map));
    // Не найденные (нет сети) попробуем при следующем изменении списков.
    _requested = _requested.difference(missing.difference(map.keys.toSet()));
  }

  List<LibraryEntry> _entriesFor(ListStatus status) {
    final list = [
      for (final e in _library.entries)
        if (e.status == status ||
            (status == ListStatus.current && e.status == ListStatus.repeating))
          e,
    ];
    int byTitle(LibraryEntry a, LibraryEntry b) =>
        (_summaries[a.mediaId]?.title.preferred ?? '').toLowerCase().compareTo(
          (_summaries[b.mediaId]?.title.preferred ?? '').toLowerCase(),
        );
    switch (_sort) {
      case ListsSort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ListsSort.score:
        list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
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
          listenable: Listenable.merge([_library, _tabs]),
          builder: (context, _) {
            final counts = _library.counts;
            final status = statusBarOrder[_tabs.index];
            final entries = _entriesFor(status);
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
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (!_library.isLoaded)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: statusIcon(status),
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
                        gridDelegate: posterGridDelegate(c.crossAxisExtent),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final a = _summaries[entries[i].mediaId];
                          return a == null
                              ? const PosterCardSkeleton()
                              : PosterCard(
                                  anime: a,
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
                        entry: entries[i],
                        anime: _summaries[entries[i].mediaId],
                        note: _notes[entries[i].mediaId],
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
    required this.entry,
    required this.anime,
    required this.note,
    required this.onTap,
  });

  final LibraryEntry entry;
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
          showStatusContextMenu(context, d.globalPosition, entry.mediaId),
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
              child: NetworkCover(
                url: a?.coverImage.medium ?? a?.coverImage.best,
                color: a?.coverImage.color,
                radius: AppRadius.xs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a?.title.preferred ?? 'Тайтл #${entry.mediaId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong,
                  ),
                  Text(
                    note?.summary.isNotEmpty ?? false
                        ? note!.summary.replaceAll('\n', ' ')
                        : 'обновлено ${Fmt.dayMonth(entry.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: t.fg2),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                '${entry.progress} / ${total ?? '?'}',
                textAlign: TextAlign.right,
                style: AppText.label.copyWith(fontFeatures: AppText.tabular),
              ),
            ),
            const SizedBox(width: 16),
            ScoreBadge(score: a?.averageScore),
            const SizedBox(width: 12),
            ListStatusDot(status: entry.status, size: 22),
          ],
        ),
      ),
    );
  }
}
