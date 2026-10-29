import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/models/anime.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'badges.dart';
import 'cover_image.dart';
import 'skeleton.dart';

/// Постер тайтла 2:3 с рейтингом, бейджем 18+ и подписью.
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  /// Высота подписи под обложкой: 2 строки названия + строка caption.
  static const captionHeight = 8 + 18 * 2 + 2 + 16.0;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = widget.anime;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

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
              url: a.coverImage.best,
              color: a.coverImage.color,
              radius: AppRadius.md - 2,
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScoreBadge(score: a.averageScore, onPoster: true),
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
                height: PosterCard.captionHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      a.title.preferred,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelStrong.copyWith(color: t.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.posterCaption(a),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
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
SliverGridDelegate posterGridDelegate(double width) =>
    _PosterGridDelegate(AppLayout.posterGap(width));

class _PosterGridDelegate extends SliverGridDelegate {
  const _PosterGridDelegate(this.gap);

  final double gap;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final w = constraints.crossAxisExtent;
    final columns = posterColumns(w);
    final itemWidth = (w - gap * (columns - 1)) / columns;
    final itemHeight = itemWidth * 3 / 2 + PosterCard.captionHeight;
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
  bool shouldRelayout(_PosterGridDelegate old) => old.gap != gap;
}
