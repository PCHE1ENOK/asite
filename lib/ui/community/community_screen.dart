import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
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

/// «Сообщество»: ролики зрителей с YouTube — эдиты, обзоры, смешные
/// моменты. Общий раздел или по тайтлу из «Моих списков». Только
/// просмотр во встроенном плеере YouTube, без комментариев.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  var _section = CommunitySection.edits;

  /// Тайтл раздела; `null` — «Все аниме».
  Anime? _title;
  List<Anime?> _titles = const [null];
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
    _loadTitles();
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

  Future<void> _loadTitles() async {
    final scope = AppScope.of(context);
    final ids = scope.library.ids;
    if (ids.isEmpty) return;
    final map = await scope.services.anime.getSummaries(ids);
    if (!mounted) return;
    final list = map.values.toList()
      ..sort(
        (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
      );
    setState(() => _titles = [null, ...list]);
  }

  String _name(Anime? a) {
    if (a == null) return 'Все аниме';
    return AppScope.of(context).services.shiki.of(a.id).value?.title ??
        a.title.preferred;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _result = null);
    final scope = AppScope.of(context);
    final r = await scope.services.community.find(
      _section,
      // В запрос — ромадзи/английское: так ролики ищутся лучше.
      title: _title == null
          ? null
          : _title!.title.romaji ?? _title!.title.preferred,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        final compact = width < AppLayout.medium;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? 16 : 28,
                gutter,
                16,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Сообщество',
                      style: compact ? AppText.headline : AppText.displayStyle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ролики зрителей с YouTube: эдиты, обзоры, смешные '
                      'моменты. Безопасный поиск, только встраиваемые ролики',
                      style: AppText.label.copyWith(color: t.fg2),
                    ),
                    const SizedBox(height: 16),
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
                        PillMenu<Anime?>(
                          label: _name(_title),
                          items: _titles,
                          value: _title,
                          itemLabel: _name,
                          selected: _title != null,
                          onSelected: (a) {
                            setState(() => _title = a);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ..._body(context, gutter),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, double gutter) {
    final pad = EdgeInsets.symmetric(horizontal: gutter);
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    switch (_result) {
      case null:
        return [
          SliverPadding(
            padding: pad,
            sliver: _grid(6, (_) => const _VideoCardSkeleton()),
          ),
        ];
      case CommunityNotConfigured():
        return [
          fill(
            const EmptyState(
              icon: Symbols.videocam_off_rounded,
              text: 'Нет ключа YouTube — ролики сообщества не загружаются',
            ),
          ),
        ];
      case CommunityQuotaExceeded():
        return [
          fill(
            const EmptyState(
              icon: Symbols.hourglass_empty_rounded,
              text: 'Лимит поиска исчерпан, попробуйте завтра',
            ),
          ),
        ];
      case CommunityFailed():
        return [
          fill(
            ErrorState(
              message: 'Не удалось загрузить ролики. Проверьте подключение',
              onRetry: _load,
            ),
          ),
        ];
      case CommunityLoaded(:final videos) when videos.isEmpty:
        return [
          fill(
            const EmptyState(
              icon: Symbols.search_off_rounded,
              text: 'В этом разделе пока ничего нет',
            ),
          ),
        ];
      case CommunityLoaded(:final videos):
        return [
          SliverPadding(
            padding: pad,
            sliver: _grid(
              videos.length,
              (i) =>
                  _VideoCard(video: videos[i], onTap: () => _open(videos[i])),
            ),
          ),
        ];
    }
  }

  Widget _grid(int count, Widget Function(int) item) => SliverGrid.builder(
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
