import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../title/episode_actions.dart';
import '../title/episode_list.dart';

/// Плеер без источников (design/screens.md §10, состояние «пусто»).
class NoSourcesScreen extends StatelessWidget {
  const NoSourcesScreen({
    super.key,
    required this.details,
    required this.episode,
  });

  final AnimeDetails details;
  final int episode;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final info = buildEpisodes(details)
        .where((e) => e.number == episode)
        .firstOrNull;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppScope.of(context).services.shiki.of(details.id).value?.title ??
                  details.anime.title.preferred,
              style: AppText.labelStrong.copyWith(color: Colors.white),
            ),
            Text(
              ['Серия $episode', ?info?.title].join(' · '),
              style: AppText.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: ListenableBuilder(
              listenable: AppScope.of(context).library,
              builder: (context, _) {
                final progress =
                    AppScope.of(context).library[details.id]?.progress ?? 0;
                final watched = episode <= progress;
                final configured = AppScope.of(context)
                    .services
                    .sources
                    .anyConfigured;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.videocam_off_rounded, size: 48, color: t.fg3),
                    const SizedBox(height: 16),
                    Text(
                      configured
                          ? 'Официального бесплатного видео не нашлось'
                          : 'Нет ключа YouTube',
                      style: AppText.title,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      configured
                          ? 'Официальные каналы Muse Asia и Ani-One Asia не '
                                'выложили эту серию или она закрыта в вашем '
                                'регионе. Каталог, списки и прогресс работают'
                          : 'Без ключа YouTube Data API официальные видео не '
                                'ищутся. Каталог, списки и прогресс работают',
                      style: AppText.body.copyWith(color: t.fg2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: watched
                          ? null
                          : () => toggleEpisodeWatched(
                              context,
                              details,
                              episode,
                              watched: false,
                            ),
                      icon: const Icon(Symbols.check_rounded),
                      label: Text(
                        watched
                            ? 'Серия $episode просмотрена'
                            : 'Отметить серию $episode просмотренной',
                      ),
                    ),
                    if (configured) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Symbols.refresh_rounded),
                        label: const Text('Проверить снова'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Вернуться к тайтлу'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
