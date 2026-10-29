import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/ui/title/episode_list.dart';
import 'package:flutter_test/flutter_test.dart';

AnimeDetails details({
  int? episodes,
  String status = 'FINISHED',
  NextAiringEpisode? next,
  List<AiringEpisode> airing = const [],
  List<StreamingEpisode> streaming = const [],
}) => AnimeDetails(
  anime: Anime(
    id: 1,
    title: const AnimeTitle(romaji: 'X'),
    episodes: episodes,
    status: status,
  ),
  nextAiringEpisode: next,
  airingSchedule: airing,
  streamingEpisodes: streaming,
);

void main() {
  test('finished show: all episodes aired, titles matched by number', () {
    final list = buildEpisodes(
      details(
        episodes: 3,
        streaming: const [
          StreamingEpisode(title: 'Episode 2 - Second'),
          StreamingEpisode(title: 'Episode 1 - First'),
        ],
      ),
    );
    expect(list.map((e) => e.number), [1, 2, 3]);
    expect(list.map((e) => e.title), ['First', 'Second', null]);
    expect(list.every((e) => e.aired), isTrue);
  });

  test('releasing show: aired up to next episode, dates for upcoming', () {
    final at = DateTime.utc(2026, 11, 3);
    final list = buildEpisodes(
      details(
        episodes: 12,
        status: 'RELEASING',
        next: NextAiringEpisode(episode: 6, airingAt: at),
        airing: [
          AiringEpisode(episode: 7, airingAt: at.add(const Duration(days: 7))),
        ],
      ),
    );
    expect(list, hasLength(12));
    expect(list.where((e) => e.aired).length, 5);
    expect(list[5].airingAt, at);
    expect(list[6].airingAt, at.add(const Duration(days: 7)));
    expect(list[11].airingAt, isNull);
  });

  test('unknown episode count uses known numbers', () {
    final list = buildEpisodes(
      details(
        status: 'RELEASING',
        next: NextAiringEpisode(episode: 4, airingAt: DateTime.utc(2026)),
      ),
    );
    expect(list, hasLength(4));
    expect(list.last.aired, isFalse);
  });

  test('announced show has no aired episodes; no data → empty', () {
    expect(
      buildEpisodes(details(episodes: 2, status: 'NOT_YET_RELEASED'))
          .any((e) => e.aired),
      isFalse,
    );
    expect(buildEpisodes(details()), isEmpty);
  });
}
