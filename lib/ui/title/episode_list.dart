import '../../data/models/anime.dart';

/// Серия в списке на вкладке «Серии».
class EpisodeInfo {
  const EpisodeInfo({
    required this.number,
    this.title,
    required this.aired,
    this.airingAt,
  });

  final int number;

  /// Название со стриминговой площадки AniList, если есть.
  final String? title;
  final bool aired;

  /// Дата выхода для ещё не вышедшей серии, если известна.
  final DateTime? airingAt;
}

/// Список серий по данным AniList: число серий, расписание выхода и
/// названия из `streamingEpisodes`. Если число серий неизвестно, берётся
/// максимум из известных номеров.
List<EpisodeInfo> buildEpisodes(AnimeDetails d) {
  final a = d.anime;
  final titles = <int, String>{};
  for (final e in d.streamingEpisodes) {
    final n = e.number;
    if (n != null && e.cleanTitle.isNotEmpty) {
      titles.putIfAbsent(n, () => e.cleanTitle);
    }
  }
  final airing = {for (final e in d.airingSchedule) e.episode: e.airingAt};
  final next = d.nextAiringEpisode;
  if (next != null) airing.putIfAbsent(next.episode, () => next.airingAt);

  final known = [?a.episodes, ?next?.episode, ...titles.keys, ...airing.keys];
  if (known.isEmpty) return const [];
  final count = known.reduce((x, y) => x > y ? x : y);

  // Сколько серий уже вышло.
  final int released;
  if (a.status == 'NOT_YET_RELEASED') {
    released = 0;
  } else if (next != null) {
    released = next.episode - 1;
  } else if (a.status == 'RELEASING' && airing.isNotEmpty) {
    released = airing.keys.reduce((x, y) => x < y ? x : y) - 1;
  } else {
    released = count;
  }

  return [
    for (var n = 1; n <= count; n++)
      EpisodeInfo(
        number: n,
        title: titles[n],
        aired: n <= released,
        airingAt: n <= released ? null : airing[n],
      ),
  ];
}
