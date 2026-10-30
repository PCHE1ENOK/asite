import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/anime.dart';
import '../../data/sources/video_source.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../title/episode_actions.dart';

/// Официальное видео правообладателя во встроенном плеере YouTube.
///
/// Видео проигрывает только плеер YouTube (iframe в WebView); приложение
/// не получает и не воспроизводит поток. Где WebView недоступен
/// (Windows без WebView2-плагина), ролик открывается на youtube.com.
class YouTubePlayerScreen extends StatelessWidget {
  const YouTubePlayerScreen({
    super.key,
    required this.video,
    required this.details,
  });

  final EmbeddedVideo video;
  final AnimeDetails details;

  /// Платформы, где `webview_flutter` встраивает плеер.
  static bool get canEmbed =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final episode = video.episode;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              details.anime.title.preferred,
              style: AppText.labelStrong.copyWith(color: Colors.white),
            ),
            Text(
              [
                if (episode != null) 'Серия $episode',
                'Официальное видео · ${video.channel}',
              ].join(' · '),
              style: AppText.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть на YouTube',
            color: Colors.white,
            onPressed: () =>
                launchUrl(video.watchUrl, mode: LaunchMode.externalApplication),
            icon: const Icon(Symbols.open_in_new_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: canEmbed
                  ? _EmbeddedPlayer(url: video.embedUrl)
                  : _OpenOnYouTube(video: video),
            ),
            if (episode != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ListenableBuilder(
                  listenable: AppScope.of(context).library,
                  builder: (context, _) {
                    final progress =
                        AppScope.of(context).library[details.id]?.progress ?? 0;
                    final watched = episode <= progress;
                    return FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: t.surface3,
                        foregroundColor: Colors.white,
                      ),
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
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmbeddedPlayer extends StatefulWidget {
  const _EmbeddedPlayer({required this.url});

  final Uri url;

  @override
  State<_EmbeddedPlayer> createState() => _EmbeddedPlayerState();
}

class _EmbeddedPlayerState extends State<_EmbeddedPlayer> {
  late final _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..loadRequest(widget.url);

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: WebViewWidget(controller: _controller),
    ),
  );
}

class _OpenOnYouTube extends StatelessWidget {
  const _OpenOnYouTube({required this.video});

  final EmbeddedVideo video;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.smart_display_rounded, size: 56, color: t.fg3),
            const SizedBox(height: 16),
            Text(
              video.title,
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Видео откроется в официальном плеере на youtube.com',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => launchUrl(
                video.watchUrl,
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Symbols.play_arrow_rounded, fill: 1),
              label: const Text('Смотреть на YouTube'),
            ),
          ],
        ),
      ),
    );
  }
}
