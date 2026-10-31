import 'anime.dart';

/// Откуда оценка: Shikimori, если там есть, иначе AniList.
enum ScoreSource {
  shikimori('Shikimori', 'Shiki'),
  anilist('AniList', 'AL');

  const ScoreSource(this.label, this.short);

  /// Полная подпись («Оценка · Shikimori») и короткая для бейджа.
  final String label;
  final String short;
}

/// Оценка по шкале 0–10 (design/screens.md: «Шкала»).
class Score10 {
  const Score10(this.value, this.source);

  final double value;
  final ScoreSource source;

  /// Shikimori (0–10), если оценка есть и не 0; иначе AniList
  /// `averageScore / 10`; нет ни той, ни другой — `null` (бейджа нет).
  static Score10? pick(Anime a, double? shikimori) {
    if (shikimori != null && shikimori > 0) {
      return Score10(shikimori, ScoreSource.shikimori);
    }
    final al = a.averageScore;
    if (al != null && al > 0) return Score10(al / 10, ScoreSource.anilist);
    return null;
  }

  /// Один знак после запятой: «8,5».
  String get text => value.toStringAsFixed(1).replaceAll('.', ',');

  @override
  bool operator ==(Object other) =>
      other is Score10 && other.value == value && other.source == source;

  @override
  int get hashCode => Object.hash(value, source);
}
