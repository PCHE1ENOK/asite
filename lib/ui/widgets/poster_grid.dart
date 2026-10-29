import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../paged_anime_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'poster_card.dart';
import 'state_views.dart';

/// Прокручиваемая сетка постеров с догрузкой, скелетонами, пустым
/// состоянием и ошибкой. Общая для каталога и поиска.
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.controller,
    required this.gutter,
    required this.onOpenTitle,
    this.header = const [],
    required this.emptyText,
    this.emptyHint,
    this.emptyActionLabel,
    this.onEmptyAction,
    required this.errorText,
    this.errorHint,
    this.skeletonCount = 18,
  });

  final PagedAnimeController controller;
  final double gutter;
  final ValueChanged<Anime> onOpenTitle;
  final List<Widget> header;
  final String emptyText;
  final String? emptyHint;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String errorText;
  final String? errorHint;
  final int skeletonCount;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final items = c.items;
    final padding = EdgeInsets.symmetric(horizontal: gutter);

    final List<Widget> body;
    if (c.isInitialLoading) {
      body = [
        SliverPadding(
          padding: padding,
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid(
              gridDelegate: posterGridDelegate(constraints.crossAxisExtent),
              delegate: SliverChildBuilderDelegate(
                (_, _) => const PosterCardSkeleton(),
                childCount: skeletonCount,
              ),
            ),
          ),
        ),
      ];
    } else if (items.isEmpty && c.error != null) {
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            message: errorText,
            hint: errorHint,
            onRetry: c.retry,
          ),
        ),
      ];
    } else if (items.isEmpty) {
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Symbols.search_off_rounded,
            text: emptyText,
            hint: emptyHint,
            actionLabel: emptyActionLabel,
            onAction: onEmptyAction,
          ),
        ),
      ];
    } else {
      body = [
        if (c.isStale)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
              child: _StaleNote(),
            ),
          ),
        SliverPadding(
          padding: padding,
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final delegate = posterGridDelegate(constraints.crossAxisExtent);
              final loadingMore = c.isLoading || (c.hasMore && c.error == null);
              return SliverGrid(
                gridDelegate: delegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i >= items.length) return const PosterCardSkeleton();
                    final a = items[i];
                    return PosterCard(
                      key: ValueKey(a.id),
                      anime: a,
                      onTap: () => onOpenTitle(a),
                    );
                  },
                  childCount:
                      items.length +
                      (loadingMore
                          ? _rowFill(constraints.crossAxisExtent, items.length)
                          : 0),
                ),
              );
            },
          ),
        ),
        if (c.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    errorText,
                    style: AppText.label.copyWith(color: context.tokens.fg2),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: c.retry,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
      ];
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 800 && c.hasMore && c.error == null) {
          c.loadMore();
        }
        return false;
      },
      child: Scrollbar(
        child: CustomScrollView(
          slivers: [
            ...header,
            ...body,
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  /// Сколько скелетонов добавить, чтобы закончить ряд и показать ещё один.
  static int _rowFill(double width, int count) {
    final columns = posterColumns(width);
    final rest = count % columns;
    return (rest == 0 ? 0 : columns - rest) + columns;
  }
}

class _StaleNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(Symbols.cloud_off_rounded, size: 18, color: t.warn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Нет сети: показаны сохранённые данные',
            style: AppText.label.copyWith(color: t.fg2),
          ),
        ),
      ],
    );
  }
}
