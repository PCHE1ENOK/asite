import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
import '../app_scope.dart';
import '../library_index.dart';
import '../russian_titles.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'badges.dart';
import 'cover_image.dart';
import 'favorite_button.dart';
import 'skeleton.dart';
import 'status_widgets.dart';
import 'verdict_visuals.dart';

/// Постер тайтла 2:3 с рейтингом, бейджем 18+ и подписью.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.note,
  });

  final Anime anime;
  final VoidCallback onTap;

  /// Заметка профиля («Мои списки»): значок вердикта и итог под названием.
  final TitleNote? note;

  /// Высота подписи под обложкой: 2 строки названия + строка caption.
  static const captionHeight = 8 + 18 * 2 + 2 + 16.0;

  /// Дополнительная высота под итог заметки (до 2 строк).
  static const noteHeight = 4 + 16 * 2.0;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;
  bool _focus = false;

  /// Списки пользователя: карточка пересобирается, только когда меняется
  /// запись этого тайтла, а не при любом изменении списков.
  LibraryIndex? _library;
  (ListStatus, int)? _seen;

  (ListStatus, int)? _snapshot() => switch (_library?[widget.anime.id]) {
    final e? => (e.status, e.progress),
    null => null,
  };

  void _onLibrary() {
    final now = _snapshot();
    if (now != _seen) setState(() => _seen = now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final library = AppScope.of(context).library;
    if (!identical(library, _library)) {
      _library?.removeListener(_onLibrary);
      _library = library..addListener(_onLibrary);
    }
    _seen = _snapshot();
  }

  @override
  void didUpdateWidget(PosterCard old) {
    super.didUpdateWidget(old);
    if (old.anime.id != widget.anime.id) _seen = _snapshot();
  }

  @override
  void dispose() {
    _library?.removeListener(_onLibrary);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = widget.anime;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final entry = _library?[a.id];
    final watching =
        entry != null &&
        (entry.status == ListStatus.current ||
            entry.status == ListStatus.repeating);
    final total = a.episodes;
    final phone = MediaQuery.sizeOf(context).width < AppLayout.medium;

    final cover = AnimatedScale(
      scale: _hover && !reduceMotion ? 1.03 : 1,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: _hover ? t.shadowE2 : null,
          border: _focus
              ? Border.all(color: t.accent, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkCover(
              cover: a.coverImage,
              color: a.coverImage.color,
              radius: AppRadius.md - 2,
            ),
            if (entry != null)
              Positioned(
                right: 8,
                top: 8,
                child: ListStatusDot(status: entry.status),
              ),
            // Сердце под точкой статуса: отмеченное видно всегда,
            // неотмеченное — на телефоне всегда, на ПК при наведении и фокусе.
            Positioned(
              right: 4,
              top: entry != null ? 34 : 4,
              child: FavoriteButton(
                anime: a,
                onPoster: true,
                visibleWhenOff: _hover || _focus || phone,
              ),
            ),
            if (watching && total != null && total > 0 && entry.progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.md - 2),
                  ),
                  child: LinearProgressIndicator(
                    value: (entry.progress / total).clamp(0, 1),
                    minHeight: 3,
                    color: t.status[ListStatus.current],
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
              ),
            if (widget.note case final n?)
              Positioned(
                right: 8,
                bottom: watching ? 10 : 8,
                child: VerdictBadge(verdict: n.verdict),
              ),
            Positioned(
              left: 8,
              top: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimeScoreBadge(anime: a, onPoster: true),
                  if (a.isAdult) ...[
                    const SizedBox(height: 4),
                    const AdultBadge(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: [
        a.title.preferred,
        Fmt.posterCaption(a),
        if (a.averageScore != null) 'рейтинг ${a.averageScore}',
        if (a.isAdult) '18+',
        if (entry != null) 'в списке: ${Fmt.status(entry.status)}',
      ].join(', '),
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: (d) =>
              showStatusContextMenu(context, d.globalPosition, a.id),
          onLongPressStart: (d) =>
              showStatusContextMenu(context, d.globalPosition, a.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Обложка всегда 2:3, подпись — фиксированной высоты, чтобы
              // ряды сетки были ровными при любой длине названия.
              Expanded(
                child: Center(
                  child: AspectRatio(aspectRatio: 2 / 3, child: cover),
                ),
              ),
              SizedBox(
                height:
                    PosterCard.captionHeight +
                    (widget.note == null ? 0 : PosterCard.noteHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    AnimeTitleText(
                      a,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelStrong.copyWith(color: t.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      watching && entry.progress > 0
                          ? Fmt.posterCaption(a, progress: entry.progress)
                          : Fmt.posterCaption(a),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                    if (widget.note?.summary.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 4),
                            child: Icon(
                              Symbols.edit_rounded,
                              size: 12,
                              color: t.fg3,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.note!.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(color: t.fg2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Скелетон карточки той же геометрии.
class PosterCardSkeleton extends StatelessWidget {
  const PosterCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Skeleton(radius: AppRadius.md),
          ),
        ),
      ),
      SizedBox(
        height: PosterCard.captionHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 10),
            Skeleton(height: 14, radius: AppRadius.xs),
            SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: 0.6,
              alignment: Alignment.centerLeft,
              child: Skeleton(height: 12, radius: AppRadius.xs),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Число колонок сетки постеров для ширины [width].
int posterColumns(double width) {
  final gap = AppLayout.posterGap(width);
  // На телефоне — 3 колонки, как в дизайне; иначе от минимальной ширины.
  var columns = width < AppLayout.medium
      ? 3
      : ((width + gap) / (AppLayout.posterMin + gap)).floor();
  // Не шире максимальной ширины карточки.
  while ((width - gap * (columns - 1)) / columns > AppLayout.posterMax) {
    columns++;
  }
  return columns.clamp(2, 12);
}

/// Делегат сетки постеров: ширина карточки 148–220, обложка 2:3.
/// [extraCaption] — место под итог заметки.
SliverGridDelegate posterGridDelegate(
  double width, {
  double extraCaption = 0,
}) => _PosterGridDelegate(AppLayout.posterGap(width), extraCaption);

class _PosterGridDelegate extends SliverGridDelegate {
  const _PosterGridDelegate(this.gap, this.extraCaption);

  final double gap;
  final double extraCaption;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final w = constraints.crossAxisExtent;
    final columns = posterColumns(w);
    final itemWidth = (w - gap * (columns - 1)) / columns;
    final itemHeight =
        itemWidth * 3 / 2 + PosterCard.captionHeight + extraCaption;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: itemHeight + gap * 1.2,
      crossAxisStride: itemWidth + gap,
      childMainAxisExtent: itemHeight,
      childCrossAxisExtent: itemWidth,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(_PosterGridDelegate old) =>
      old.gap != gap || old.extraCaption != extraCaption;
}
