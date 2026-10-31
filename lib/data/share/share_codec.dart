import 'dart:convert';

import '../models/anime.dart';
import '../models/favorite.dart';
import '../models/library_entry.dart';
import '../models/score.dart';
import '../models/title_note.dart';
import '../shikimori/russian_text.dart';

/// `share.json` — каталог профиля для друзей (docs/friends/SHARE_FORMAT.md).
///
/// В файл попадают только данные каталога: названия, обложки, статусы,
/// «Понравилось», оценки, заметки. Никаких токенов, Client ID, ключей API,
/// логина GitHub и id приватного Gist — функции их даже не получают.
abstract final class ShareCodec {
  static const fileName = 'share.json';
  static const description =
      'Anime Viewer: каталог для друзей (только просмотр)';
  static const version = 1;

  static String _verdict(NoteVerdict v) => switch (v) {
    NoteVerdict.rewatch => 'rewatch',
    NoteVerdict.recommend => 'recommend',
    NoteVerdict.notRecommend => 'not',
    NoteVerdict.none => 'none',
  };

  static String _time(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// Все тайтлы профиля: из списков, «Понравилось» и заметок (удалённые
  /// не попадают). Тайтлы 18+ включены с пометкой `adult`.
  static Map<String, dynamic> build({
    required String owner,
    required DateTime now,
    required List<LibraryEntry> entries,
    required List<Favorite> favorites,
    required List<TitleNote> notes,
    required Map<int, Anime> summaries,
    Map<int, ShikiInfo> shikimori = const {},
    Map<int, String> trailers = const {},
  }) {
    final byEntry = {
      for (final e in entries)
        if (!e.deleted) e.mediaId: e,
    };
    final fav = {
      for (final f in favorites)
        if (!f.deleted) f.mediaId,
    };
    final byNote = {
      for (final n in notes)
        if (!n.deleted && !n.isEmpty) n.mediaId: n,
    };
    final ids = {...byEntry.keys, ...fav, ...byNote.keys}.toList()..sort();
    final titles = <Map<String, dynamic>>[];
    for (final id in ids) {
      final a = summaries[id];
      if (a == null) continue; // без карточки AniList показать нечего
      final e = byEntry[id];
      final n = byNote[id];
      final sh = shikimori[id];
      final score = Score10.pick(a, sh?.score);
      final updated = [
        ?e?.updatedAt,
        ?n?.updatedAt,
        for (final f in favorites)
          if (f.mediaId == id) f.updatedAt,
      ]..sort();
      titles.add({
        'id': id,
        'title': {
          'ru': ?sh?.title,
          'en': ?a.title.english,
          'romaji': ?a.title.romaji,
        },
        'cover': ?(a.coverImage.large ?? a.coverImage.best),
        'coverColor': ?a.coverImage.color,
        'format': ?a.format,
        'year': ?a.seasonYear,
        'episodes': ?a.episodes,
        if (score != null)
          'score': {
            'value': double.parse(score.value.toStringAsFixed(1)),
            'source': score.source == ScoreSource.shikimori
                ? 'shikimori'
                : 'anilist',
          },
        if (e != null) 'status': e.status.apiValue,
        if (e != null) 'progress': e.progress,
        'favorite': fav.contains(id),
        'adult': a.isAdult,
        if (updated.isNotEmpty)
          'updatedAt': updated.last.toUtc().toIso8601String(),
        'trailer': ?trailers[id],
        if (n != null)
          'note': {
            'verdict': _verdict(n.verdict),
            if (n.summary.isNotEmpty) 'summary': n.summary,
            if (n.liked.isNotEmpty) 'liked': n.liked,
            if (n.dropReasons.isNotEmpty) 'dropReasons': n.dropReasons,
            if (n.dropText.isNotEmpty) 'dropText': n.dropText,
            if (n.moments.isNotEmpty)
              'moments': [
                for (final m in n.moments)
                  {
                    'episode': m.episode,
                    if (m.timecode != null) 'time': _time(m.timecode!),
                    'text': m.text,
                  },
              ],
          },
      });
    }
    return {
      'version': version,
      'owner': owner,
      'updatedAt': now.toUtc().toIso8601String(),
      'titles': titles,
    };
  }

  static String encode(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent(' ').convert(json);
}
