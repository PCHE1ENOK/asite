import 'package:flutter/material.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../app_scope.dart';
import '../format.dart';

/// Отмечает серию просмотренной или снимает отметку; тост с «Отменить».
/// Тот же путь использует плеер (автоотметка на 85%) и экран «Источники
/// видео не подключены».
Future<void> toggleEpisodeWatched(
  BuildContext context,
  AnimeDetails d,
  int episode, {
  required bool watched,
}) async {
  final library = AppScope.of(context).services.library;
  final messenger = ScaffoldMessenger.of(context);
  final r = watched
      ? await library.unmarkWatched(d.id, episode)
      : await library.markWatched(
          d.id,
          episode,
          totalEpisodes: d.anime.episodes,
        );
  final statusNote = r.before?.status == r.after.status
      ? ''
      : r.after.status == ListStatus.completed
      ? ' · тайтл просмотрен'
      : r.before == null
      ? ' · статус «Смотрю»'
      : ' · статус «${Fmt.status(r.after.status)}»';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          watched
              ? 'Отметка с серии $episode снята$statusNote'
              : 'Серия $episode отмечена просмотренной$statusNote',
        ),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => library.restore(d.id, r.before),
        ),
      ),
    );
}
