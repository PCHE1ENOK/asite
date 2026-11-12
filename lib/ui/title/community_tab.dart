import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/sources/community_videos.dart';
import '../../data/sources/video_source.dart';
import '../app_scope.dart';
import '../player/youtube_player_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/filter_controls.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Вкладка «Сообщество» карточки тайтла: ролики зрителей с YouTube об
/// этом тайтле — эдиты, обзоры, смешные моменты. Только просмотр во
/// встроенном плеере YouTube, без комментариев.
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key, required this.title});

  /// Название тайтла для поиска.
  final String title;

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  var _section = CommunitySection.edits;
  CommunityResult? _result;
  int _generation = 0;
  bool _started = false;
  AppSettings? _settings;
  bool? _lastAdult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _settings = AppScope.of(context).settings..addListener(_onSettings);
    _lastAdult = _settings!.showAdult;
    _load();
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettings);
    super.dispose();
  }

  /// «Показывать 18+» меняет и эту вкладку (из кэша, без нового поиска).
  void _onSettings() {
    if (_settings!.showAdult != _lastAdult) {
      _lastAdult = _settings!.showAdult;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _result = null);
    final scope = AppScope.of(context);
    final r = await scope.services.community.find(
      _section,
      title: widget.title,
      showAdult: scope.settings.showAdult,
    );
    if (mounted && generation == _generation) setState(() => _result = r);
  }

  void _open(EmbeddedVideo v) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => YouTubePlayerScreen(video: v)),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ролики зрителей с YouTube. Безопасный поиск, только '
          'встраиваемые ролики',
          style: AppText.label.copyWith(color: t.fg2),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in CommunitySection.values)
              PillButton(
                label: s.label,
                selected: s == _section,
                onPressed: () {
                  if (s == _section) return;
                  setState(() => _section = s);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _body(),
      ],
    );
  }

  Widget _body() => switch (_result) {
    null => _grid(6, (_) => const _VideoCardSkeleton()),
    CommunityNotConfigured() => const EmptyState(
      icon: Symbols.videocam_off_rounded,
      text: 'Нет ключа YouTube — ролики сообщества не загружаются',
    ),
    CommunityQuotaExceeded() => const EmptyState(
      icon: Symbols.hourglass_empty_rounded,
      text: 'Лимит поиска исчерпан, попробуйте завтра',
    ),
    CommunityFailed() => ErrorState(
      message: 'Не удалось загрузить ролики. Проверьте подключение',
      onRetry: _load,
    ),
    CommunityLoaded(:final videos) when videos.isEmpty => const EmptyState(
      icon: Symbols.search_off_rounded,
      text: 'В этом разделе пока ничего нет',
    ),
    CommunityLoaded(:final videos) => _grid(
      videos.length,
      (i) => _VideoCard(video: videos[i], onTap: () => _open(videos[i])),
    ),
  };

  Widget _grid(int count, Widget Function(int) item) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 360,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 16 / 13,
    ),
    itemCount: count,
    itemBuilder: (_, i) => item(i),
  );
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});

  final EmbeddedVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: '${video.title}, ${video.channel}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkCover(url: video.thumbnail),
                  Center(
                    child: Icon(
                      Symbols.play_circle_rounded,
                      size: 44,
                      fill: 1,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelStrong.copyWith(color: t.fg),
            ),
            const SizedBox(height: 2),
            Text(
              video.channel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: t.fg2),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCardSkeleton extends StatelessWidget {
  const _VideoCardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Skeleton(radius: AppRadius.md),
      ),
      SizedBox(height: 10),
      Skeleton(height: 14),
      SizedBox(height: 6),
      FractionallySizedBox(
        widthFactor: 0.5,
        alignment: Alignment.centerLeft,
        child: Skeleton(height: 12),
      ),
    ],
  );
}
