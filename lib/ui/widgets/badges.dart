import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../../data/models/score.dart';
import '../../data/shikimori/russian_text.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Оценка 0–10 с одним знаком и короткой подписью источника («8,6 AL»,
/// «8,8 Shiki»); на постере — на тёмной подложке. Нет оценки — пусто.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, this.onPoster = false});

  final Score10? score;
  final bool onPoster;

  @override
  Widget build(BuildContext context) {
    final sc = score;
    if (sc == null) return const SizedBox.shrink();
    final t = context.tokens;
    // На постере фон всегда тёмный, поэтому берём цвета тёмной темы.
    final palette = onPoster ? AppTokens.dark : t;
    final color = palette.scoreColor(sc.value);
    final bg = onPoster
        ? AppTokens.posterBadgeBg
        : Color.alphaBlend(color.withValues(alpha: 0.12), t.surface2);
    final label = 'Оценка ${sc.text} из 10 · ${sc.source.label}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(sc.text, style: AppText.badge.copyWith(color: color)),
              const SizedBox(width: 3),
              Text(
                sc.source.short,
                style: AppText.badge.copyWith(
                  fontSize: 10,
                  color: onPoster ? const Color(0xB3FFFFFF) : palette.fg2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Бейдж оценки тайтла: Shikimori, если подгрузилась, иначе AniList.
/// Пересобирается только при приходе данных своего тайтла.
class AnimeScoreBadge extends StatelessWidget {
  const AnimeScoreBadge({
    super.key,
    required this.anime,
    this.onPoster = false,
  });

  final Anime anime;
  final bool onPoster;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ShikiInfo?>(
    valueListenable: AppScope.of(context).services.shiki.of(anime.id),
    builder: (context, info, _) =>
        ScoreBadge(score: Score10.pick(anime, info?.score), onPoster: onPoster),
  );
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
