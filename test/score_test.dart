import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/models/score.dart';
import 'package:anime_viewer/data/shikimori/shikimori_client.dart';
import 'package:anime_viewer/ui/theme/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

Anime a({int? avg}) => Anime(
  id: 1,
  averageScore: avg,
  title: const AnimeTitle(romaji: 'X'),
);

void main() {
  test('Shikimori first, AniList / 10 as fallback, none — no badge', () {
    expect(
      Score10.pick(a(avg: 85), 8.84),
      const Score10(8.84, ScoreSource.shikimori),
    );
    expect(
      Score10.pick(a(avg: 85), null),
      const Score10(8.5, ScoreSource.anilist),
    );
    expect(
      Score10.pick(a(avg: 85), 0),
      const Score10(8.5, ScoreSource.anilist),
      reason: 'zero Shikimori score is not shown',
    );
    expect(Score10.pick(a(), null), isNull);
    expect(Score10.pick(a(), 0), isNull);
    expect(Score10.pick(a(avg: 0), null), isNull);
  });

  test('one digit after a comma', () {
    expect(const Score10(8.84, ScoreSource.shikimori).text, '8,8');
    expect(const Score10(9, ScoreSource.anilist).text, '9,0');
    expect(const Score10(7.45, ScoreSource.anilist).text, '7,5');
  });

  test('colour thresholds 7.5 / 6.0 on the 0–10 scale', () {
    const t = AppTokens.dark;
    expect(t.scoreColor(7.5), t.good);
    expect(t.scoreColor(7.4), t.warn);
    expect(t.scoreColor(6.0), t.warn);
    expect(t.scoreColor(5.9), t.bad);
    expect(t.scoreColor(null), t.fg3);
  });

  test('Shikimori score: string or number, 0.0 means none', () {
    expect(ShikiAnime.fromJson({'id': 1, 'score': '8.84'})!.score, 8.84);
    expect(ShikiAnime.fromJson({'id': 1, 'score': 7})!.score, 7);
    expect(ShikiAnime.fromJson({'id': 1, 'score': '0.0'})!.score, isNull);
    expect(ShikiAnime.fromJson({'id': 1})!.score, isNull);
  });
}
