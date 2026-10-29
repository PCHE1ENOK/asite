import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/status_visuals.dart';

/// Распределение оценок AniList: 10 столбцов 10–100, один цвет `accent`.
/// Подписи на трёх самых высоких, остальное — во всплывающей подсказке.
class ScoreHistogram extends StatelessWidget {
  const ScoreHistogram({super.key, required this.buckets, this.height = 200});

  final List<ScoreBucket> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final byScore = {for (final b in buckets) b.score: b.amount};
    final scores = [for (var s = 10; s <= 100; s += 10) s];
    final amounts = [for (final s in scores) byScore[s] ?? 0];
    final max = amounts.fold(0, (a, b) => a > b ? a : b);
    final top3 = ([...amounts]..sort((a, b) => b - a)).take(3).toSet();

    return Semantics(
      label: [
        'Оценки пользователей AniList.',
        for (var i = 0; i < scores.length; i++)
          '${scores[i]} баллов: ${amounts[i]}.',
      ].join(' '),
      excludeSemantics: true,
      child: SizedBox(
        height: height + 40,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < scores.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Tooltip(
                          message:
                              '${scores[i]} баллов · ${Fmt.thousands(amounts[i])} чел.',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (amounts[i] > 0 && top3.contains(amounts[i]))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: FittedBox(
                                    child: Text(
                                      Fmt.thousands(amounts[i]),
                                      style: AppText.badge.copyWith(
                                        color: t.fg,
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                height: max == 0
                                    ? 0
                                    : (height - 24) * amounts[i] / max + 2,
                                decoration: BoxDecoration(
                                  color: t.accent,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: t.borderStrong),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in scores)
                  Expanded(
                    child: Text(
                      '$s',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Составная полоса по статусам с легендой (иконка, подпись, число, %).
class StatusDistributionBar extends StatelessWidget {
  const StatusDistributionBar({
    super.key,
    required this.amounts,
    required this.caption,
  });

  /// Распределение статусов AniList (`stats.statusDistribution`).
  factory StatusDistributionBar.fromBuckets(
    List<StatusBucket> buckets,
  ) => StatusDistributionBar(
    amounts: {for (final b in buckets) ?ListStatus.fromApi(b.status): b.amount},
    caption: (total) =>
        '${Fmt.thousands(total)} ${Fmt.plural(total, 'пользователь', 'пользователя', 'пользователей')}',
  );

  final Map<ListStatus, int> amounts;
  final String Function(int total) caption;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final segments = [
      for (final s in statusBarOrder)
        if ((amounts[s] ?? 0) > 0) (s, amounts[s]!),
    ];
    final total = segments.fold(0, (sum, e) => sum + e.$2);
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption(total), style: AppText.caption.copyWith(color: t.fg2)),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: (segments[i].$2 * 1000 / total).ceil(),
                      child: ColoredBox(color: t.status[segments[i].$1]!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final (status, amount) in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  statusIcon(status),
                  size: 18,
                  fill: 1,
                  color: t.status[status],
                ),
                const SizedBox(width: 8),
                Text(Fmt.status(status), style: AppText.label),
                const SizedBox(width: 8),
                Text(
                  Fmt.thousands(amount),
                  style: AppText.labelStrong.copyWith(
                    fontFeatures: AppText.tabular,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(amount * 100 / total).round()}%',
                  style: AppText.label.copyWith(color: t.fg2),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
