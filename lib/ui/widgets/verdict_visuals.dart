import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/title_note.dart';
import '../theme/app_tokens.dart';

/// Значок, цвет и подпись вердикта (design/screens.md §12): не только цвет.
({IconData icon, Color color, String label}) verdictVisual(
  NoteVerdict v,
  AppTokens t,
) => switch (v) {
  NoteVerdict.rewatch => (
    icon: Symbols.replay_rounded,
    color: t.accent,
    label: 'Стоит пересмотреть',
  ),
  NoteVerdict.recommend => (
    icon: Symbols.thumb_up_rounded,
    color: t.good,
    label: 'Советую',
  ),
  NoteVerdict.notRecommend => (
    icon: Symbols.thumb_down_rounded,
    color: t.bad,
    label: 'Не советую',
  ),
  NoteVerdict.none => (
    icon: Symbols.remove_rounded,
    color: t.fg3,
    label: 'Без вердикта',
  ),
};

/// Значок вердикта на постере — на тёмной подложке, как рейтинг.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge({super.key, required this.verdict});

  final NoteVerdict verdict;

  @override
  Widget build(BuildContext context) {
    // На постере подложка всегда тёмная — цвета тёмной темы.
    final v = verdictVisual(verdict, AppTokens.dark);
    return Semantics(
      label: 'Заметка: ${v.label}',
      excludeSemantics: true,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            v.color.withValues(alpha: 0.12),
            AppTokens.posterBadgeBg,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Icon(v.icon, size: 16, color: v.color, fill: 1),
      ),
    );
  }
}
