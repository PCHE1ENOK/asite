import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/sources/community_videos.dart';
import '../../data/sources/video_source.dart';
import '../../platform/platform.dart' as platform;
import '../app_scope.dart';
import '../player/youtube_player_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/filter_controls.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Вкладка «Сообщество» карточки тайтла (design/screens.md §17): ролики
/// зрителей с YouTube об этом тайтле — пересказы, эдиты, обзоры, смешные
/// моменты, только на русском. Просмотр во встроенном плеере YouTube, без
/// комментариев.
class CommunityTab extends StatefulWidget {
  const CommunityTab({
    super.key,
    required this.query,
    required this.displayTitle,
  });

  /// Название для поиска: русское, иначе ромадзи.
  final String query;

  /// Название тайтла в текстах вкладки.
  final String displayTitle;

  /// Пометка под вкладкой — всегда.
  static const note =
      'Ролики с YouTube, созданы пользователями. Не связаны с '
      'правообладателями.';

  /// Сбрасывает запомненный раздел (тесты).
  @visibleForTesting
  static void resetSection() =>
      _CommunityTabState._lastSection = CommunitySection.retell;

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  /// Выбранный раздел запоминается между тайтлами.
  static var _lastSection = CommunitySection.retell;

  var _section = _lastSection;
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
      title: widget.query,
      showAdult: scope.settings.showAdult,
    );
    if (mounted && generation == _generation) setState(() => _result = r);
  }

  void _select(CommunitySection s) {
    if (s == _section) return;
    setState(() => _section = _lastSection = s);
    _load();
  }

  void _open(EmbeddedVideo v) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => YouTubePlayerScreen(video: v)),
  );

  /// «Поиск снова заработает в 11:00».
  String _quotaHint() {
    final at = CommunityVideos.quotaResetAfter(DateTime.now());
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return 'YouTube даёт приложению ограниченное число поисков в сутки. '
        'Поиск снова заработает в $hm.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sections(phone, constraints.maxWidth),
            const SizedBox(height: 16),
            _body(constraints.maxWidth, phone),
            const SizedBox(height: 24),
            Divider(height: 1, color: t.border),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.info_rounded, size: 16, color: t.fg3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    CommunityTab.note,
                    style: AppText.caption.copyWith(color: t.fg3),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// ПК — одна строка; телефон — сетка 2×2 во всю ширину.
  Widget _sections(bool phone, double width) {
    Widget pill(CommunitySection s) => PillButton(
      label: s.label,
      selected: s == _section,
      onPressed: () => _select(s),
    );
    if (!phone) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final s in CommunitySection.values) pill(s)],
      );
    }
    final half = (width - 8) / 2;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in CommunitySection.values)
          SizedBox(width: half, child: pill(s)),
      ],
    );
  }

  Widget _body(double width, bool phone) => switch (_result) {
    null => _grid(width, phone, 4, (_) => const _VideoCardSkeleton()),
    CommunityNotConfigured() => EmptyState(
      icon: Symbols.videocam_off_rounded,
      text: 'Сообщество недоступно: не задан ключ YouTube',
      hint: platform.isWeb ? 'Укажите свой ключ в «Настройки → YouTube»' : null,
    ),
    CommunityQuotaExceeded() => EmptyState(
      icon: Symbols.hourglass_empty_rounded,
      text: 'Лимит поиска исчерпан, попробуйте завтра',
      hint: _quotaHint(),
    ),
    CommunityFailed() => ErrorState(
      message: 'Нет связи с YouTube',
      hint: 'Проверьте подключение к интернету и попробуйте ещё раз.',
      onRetry: _load,
    ),
    CommunityLoaded(:final videos) when videos.isEmpty => EmptyState(
      icon: Symbols.search_off_rounded,
      text: 'Роликов не нашлось',
      hint:
          'По «${widget.displayTitle}» в разделе «${_section.label}» пока '
          'ничего. Загляните в другой раздел.',
    ),
    CommunityLoaded(:final videos, :final quotaHit) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quotaHit) ...[
          _QuotaWarning(text: _quotaHint()),
          const SizedBox(height: 12),
        ],
        _grid(
          width,
          phone,
          videos.length,
          (i) => _VideoCard(video: videos[i], onTap: () => _open(videos[i])),
        ),
      ],
    ),
  };

  /// ПК — колонки от 260, телефон — одна колонка.
  Widget _grid(double width, bool phone, int count, Widget Function(int) item) {
    const gap = 20.0;
    final cols = phone ? 1 : ((width + gap) / (260 + gap)).floor().clamp(1, 6);
    final itemWidth = (width - gap * (cols - 1)) / cols;
    return Wrap(
      spacing: gap,
      runSpacing: 24,
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(width: itemWidth, child: item(i)),
      ],
    );
  }
}

class _QuotaWarning extends StatelessWidget {
  const _QuotaWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Symbols.hourglass_empty_rounded, size: 18, color: t.warn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Лимит поиска исчерпан — показаны сохранённые ролики. $text',
            style: AppText.label.copyWith(color: t.fg2),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});

  final EmbeddedVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: [
            video.title,
            video.channel,
            if (video.duration case final d?) _formatDuration(d),
          ].join(', '),
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
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
                    if (video.duration case final d?)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        // Как на YouTube: тёмная плашка в обеих темах.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Text(
                              _formatDuration(d),
                              style: AppText.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            ),
            SizedBox.square(
              dimension: 36,
              child: Semantics(
                label: 'Открыть «${video.title}» на YouTube',
                button: true,
                excludeSemantics: true,
                child: IconButton(
                  tooltip: 'Открыть на YouTube',
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: t.fg2,
                  onPressed: () => openExternally(context, video.watchUrl),
                  icon: const Icon(Symbols.open_in_new_rounded),
                ),
              ),
            ),
          ],
        ),
      ],
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
