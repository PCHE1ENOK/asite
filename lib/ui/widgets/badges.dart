import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Рейтинг AniList целым числом; на постере — на тёмной подложке.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.onPoster = false});

  final int? score;
  final bool onPoster;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // На постере фон всегда тёмный, поэтому берём цвета тёмной темы.
    final palette = onPoster ? AppTokens.dark : t;
    final color = palette.scoreColor(score);
    final bg = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      onPoster ? AppTokens.posterBadgeBg : t.surface2,
    );
    return Semantics(
      label: score == null ? 'Нет оценки' : 'Рейтинг AniList $score',
      excludeSemantics: true,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (score != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              score?.toString() ?? '—',
              style: AppText.badge.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// «18+» для `Media.isAdult`; одинаковый в обеих темах.
class AdultBadge extends StatelessWidget {
  const AdultBadge({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Для взрослых, 18+',
    excludeSemantics: true,
    child: Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTokens.adultBg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '18+',
        style: AppText.caption.copyWith(
          color: AppTokens.adultFg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
