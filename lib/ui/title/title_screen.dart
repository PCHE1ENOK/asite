import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/anilist/anilist_client.dart';
import '../../data/anime_repository.dart';
import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/sources/video_source.dart';
import '../app_scope.dart';
import '../format.dart';
import '../player/no_sources_screen.dart';
import '../player/youtube_player_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import '../widgets/cover_image.dart';
import '../widgets/poster_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../widgets/status_widgets.dart';
import 'episode_actions.dart';
import 'comments_tab.dart';
import 'episode_list.dart';
import 'note_editor.dart';
import 'title_charts.dart';

/// Карточка аниме (design/screens.md §3) на данных AniList.
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.id,
    this.preview,
    required this.onOpenTitle,
  });

  final int id;

  /// Краткая карточка из каталога: шапка видна сразу, пока грузятся детали.
  final Anime? preview;
  final ValueChanged<Anime> onOpenTitle;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

enum TitleTab {
  episodes('Серии'),
  description('Описание'),
  stats('Статистика'),
  comments('Комментарии'),
  similar('Похожие');

  const TitleTab(this.label);

  final String label;
}

class _TitleScreenState extends State<TitleScreen>
    with TickerProviderStateMixin {
  late TabController _tabs = TabController(
    length: _visibleTabs.length,
    vsync: this,
  );

  /// «Комментарии» есть только у тайтлов с официальным роликом YouTube.
  List<TitleTab> get _visibleTabs => [
    for (final t in TitleTab.values)
      if (t != TitleTab.comments || _videos.isNotEmpty) t,
  ];

  /// Пересоздаёт контроллер вкладок, если набор вкладок изменился,
  /// оставляя открытой ту же вкладку.
  void _syncTabs(List<TitleTab> before) {
    final after = _visibleTabs;
    if (after.length == _tabs.length) return;
    final current = before[_tabs.index];
    // Старый контроллер ещё привязан к TabBar в этом кадре.
    final old = _tabs;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _tabs = TabController(
      length: after.length,
      vsync: this,
      initialIndex: after.indexOf(current).clamp(0, after.length - 1),
    );
  }

  Cached<AnimeDetails>? _details;
  AniListException? _error;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final d = await AppScope.of(context).services.anime
          .getDetails(widget.id, forceRefresh: force);
      if (mounted) setState(() => _details = d);
      if (mounted) await _loadVideos(d.data);
    } on AniListException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Официальные видео из подключённых источников (этап 6).
  List<EmbeddedVideo> _videos = const [];

  /// Идёт поиск видео (в том числе «Проверить снова»).
  bool _videosLoading = false;

  /// Официальный трейлер; `null` — кнопки «Трейлер на YouTube» нет.
  EmbeddedVideo? _trailer;

  /// Поиск трейлера (100 единиц квоты на канал) уже запускали — кнопку
  /// «Найти трейлер» больше не показываем; ничего не нашлось — без сообщения.
  bool _trailerSearched = false;
  bool _trailerSearching = false;

  Future<void> _loadVideos(AnimeDetails d, {bool refresh = false}) async {
    setState(() => _videosLoading = true);
    final sources = AppScope.of(context).services.sources;
    if (refresh) _trailerSearched = true;
    final trailer = sources.findTrailer(d, search: refresh);
    final videos = await sources.find(d, refresh: refresh);
    if (!mounted) return;
    setState(() {
      final before = _visibleTabs;
      _videos = videos;
      _videosLoading = false;
      _syncTabs(before);
    });
    final t = await trailer;
    if (mounted) setState(() => _trailer = t);
  }

  /// «Найти трейлер»: поиск по официальным каналам — только по нажатию.
  Future<void> _searchTrailer(AnimeDetails d) async {
    setState(() {
      _trailerSearched = true;
      _trailerSearching = true;
    });
    final t = await AppScope.of(context).services.sources
        .findTrailer(d, search: true);
    if (mounted) {
      setState(() {
        _trailer = t;
        _trailerSearching = false;
      });
    }
  }

  void _playTrailer(AnimeDetails d, EmbeddedVideo trailer) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => YouTubePlayerScreen(video: trailer, details: d),
        ),
      );

  EmbeddedVideo? _videoFor(int episode) =>
      _videos.where((v) => v.episode == episode).firstOrNull;

  /// Серия, которую предлагает кнопка «Смотреть»: следующая после
  /// просмотренных, если она вышла, иначе первая.
  int _nextEpisode(AnimeDetails d) {
    final progress = AppScope.of(context).library[d.id]?.progress ?? 0;
    final episodes = buildEpisodes(d);
    final next = progress + 1;
    return next <= episodes.length && episodes[next - 1].aired ? next : 1;
  }

  String _playLabel(AnimeDetails? d) {
    if (d == null) return 'Начать просмотр';
    final progress = AppScope.of(context).library[d.id]?.progress ?? 0;
    final next = _nextEpisode(d);
    final onYouTube =
        _videoFor(next) != null ||
        (d.anime.format == 'MOVIE' && _videos.isNotEmpty);
    final base = progress > 0 && next > 1
        ? 'Смотреть серию $next'
        : 'Начать просмотр';
    return onYouTube ? '$base на YouTube' : base;
  }

  /// Официальное видео серии или экран «нет видео».
  void _play(AnimeDetails d, [int? episode]) {
    final n = episode ?? _nextEpisode(d);
    final video =
        _videoFor(n) ??
        (d.anime.format == 'MOVIE' ? _videos.firstOrNull : null);
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => video != null
                ? YouTubePlayerScreen(video: video, details: d)
                : NoSourcesScreen(details: d, episode: n),
          ),
        )
        .then((retry) {
          // «Проверить снова» на экране без видео.
          if (retry == true && mounted) _loadVideos(d, refresh: true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final details = _details?.data;
    final anime = details?.anime ?? widget.preview;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final gutter = AppLayout.gutter(width);
          if (anime == null) {
            if (_error != null) {
              return _errorView();
            }
            return const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(
            listenable: Listenable.merge([_tabs, AppScope.of(context).library]),
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    anime: anime,
                    details: details,
                    playLabel: _playLabel(details),
                    onPlay: details == null ? null : () => _play(details),
                    onTrailer: switch ((details, _trailer)) {
                      (final d?, final tr?) => () => _playTrailer(d, tr),
                      _ => null,
                    },
                    onFindTrailer:
                        details == null ||
                            _trailer != null ||
                            _trailerSearched ||
                            _videosLoading ||
                            !AppScope.of(context).services.sources.anyConfigured
                        ? null
                        : () => _searchTrailer(details),
                    trailerSearching: _trailerSearching,
                    width: width,
                    gutter: gutter,
                  ),
                ),
                if (_details?.isStale ?? false)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                      child: Text(
                        'Нет сети: показаны сохранённые данные',
                        style: AppText.label.copyWith(
                          color: context.tokens.warn,
                        ),
                      ),
                    ),
                  ),
                if (details != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
                      child: NoteBlock(
                        key: ValueKey(details.id),
                        details: details,
                        width: width,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabs: [for (final t in _visibleTabs) Tab(text: t.label)],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ..._tabBody(context, details, gutter, width),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _errorView() => Stack(
    children: [
      ErrorState(
        message: _error!.isNotFound
            ? 'Тайтл не найден на AniList'
            : 'Не удалось загрузить тайтл. Проверьте подключение',
        onRetry: () => _load(force: true),
      ),
      const SafeArea(child: BackButton()),
    ],
  );

  List<Widget> _tabBody(
    BuildContext context,
    AnimeDetails? d,
    double gutter,
    double width,
  ) {
    final pad = EdgeInsets.symmetric(horizontal: gutter);
    if (d == null) {
      if (_error != null) {
        return [
          SliverToBoxAdapter(
            child: ErrorState(
              message:
                  'Не удалось загрузить подробности. Проверьте подключение',
              onRetry: () => _load(force: true),
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: pad,
          sliver: SliverList.separated(
            itemCount: 6,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, _) => const Skeleton(height: 48),
          ),
        ),
      ];
    }
    return switch (_visibleTabs[_tabs.index]) {
      TitleTab.episodes => _episodes(context, d, pad),
      TitleTab.description => [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(child: _Description(details: d)),
        ),
      ],
      TitleTab.stats => [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(
            child: _Stats(details: d, width: width),
          ),
        ),
      ],
      TitleTab.similar => [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(
            child: _Similar(details: d, onOpenTitle: widget.onOpenTitle),
          ),
        ),
      ],
      TitleTab.comments => [
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(
            child: CommentsTab(key: ValueKey(d.id), videos: _videos),
          ),
        ),
      ],
    };
  }

  List<Widget> _episodes(BuildContext context, AnimeDetails d, EdgeInsets pad) {
    final episodes = buildEpisodes(d);
    if (episodes.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: EmptyState(
            icon: Symbols.video_library_rounded,
            text: 'AniList пока не знает число серий',
          ),
        ),
      ];
    }
    final duration = d.anime.duration;
    final progress = AppScope.of(context).library[d.id]?.progress ?? 0;
    return [
      if (_videos.isEmpty)
        SliverPadding(
          padding: pad.copyWith(bottom: 12),
          sliver: SliverToBoxAdapter(
            child: _NoVideoBanner(
              configured: AppScope.of(context).services.sources.anyConfigured,
              loading: _videosLoading,
              onRetry: () => _loadVideos(d, refresh: true),
            ),
          ),
        ),
      SliverPadding(
        padding: pad,
        sliver: SliverList.builder(
          itemCount: episodes.length,
          itemBuilder: (context, i) {
            final e = episodes[i];
            final watched = e.number <= progress;
            return _EpisodeRow(
              episode: e,
              duration: duration,
              watched: watched,
              isNext: e.aired && e.number == progress + 1,
              onToggle: e.aired ? () => _toggleEpisode(d, e, watched) : null,
              onWatch: _videoFor(e.number) == null
                  ? null
                  : () => _play(d, e.number),
            );
          },
        ),
      ),
    ];
  }

  Future<void> _toggleEpisode(AnimeDetails d, EpisodeInfo e, bool watched) =>
      toggleEpisodeWatched(context, d, e.number, watched: watched);
}

/// Почему у серий нет видео: нет ключа или официального видео не нашлось.
class _NoVideoBanner extends StatelessWidget {
  const _NoVideoBanner({
    required this.configured,
    required this.loading,
    required this.onRetry,
  });

  final bool configured;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final String text;
    if (!configured) {
      text =
          'Нет ключа YouTube — официальные видео не ищутся. Серии можно '
          'отмечать просмотренными вручную';
    } else if (loading) {
      text = 'Ищем официальное видео на YouTube…';
    } else {
      text =
          'Официального бесплатного видео для этого тайтла не нашлось '
          '(в вашем регионе). Серии можно отмечать просмотренными вручную';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (configured && loading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Symbols.videocam_off_rounded, color: t.fg3, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(text, style: AppText.label.copyWith(color: t.fg2)),
              ),
            ],
          ),
          if (configured && !loading)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh_rounded, size: 18),
              label: const Text('Проверить снова'),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.anime,
    required this.details,
    required this.playLabel,
    required this.onPlay,
    required this.width,
    required this.gutter,
    this.onTrailer,
    this.onFindTrailer,
    this.trailerSearching = false,
  });

  final Anime anime;
  final AnimeDetails? details;
  final String playLabel;
  final VoidCallback? onPlay;

  /// Трейлер есть — кнопка «Трейлер на YouTube».
  final VoidCallback? onTrailer;

  /// Трейлера в AniList нет — «Найти трейлер» (поиск по нажатию).
  final VoidCallback? onFindTrailer;
  final bool trailerSearching;
  final double width;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = anime;
    final compact = width < AppLayout.medium;
    final posterWidth = compact ? 120.0 : 220.0;
    final banner = a.bannerImage;
    final resolver = AppScope.of(context).imageResolver;

    final background = Positioned.fill(
      child: ClipRect(
        child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.55), Colors.transparent],
            stops: const [0.0, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: banner != null
              ? Image(
                  image: resolver(banner),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              : a.coverImage.forWidth(250) == null
              ? const SizedBox.shrink()
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  // Под сильным размытием большая обложка не нужна.
                  child: Image(
                    image: resolver(a.coverImage.forWidth(250)!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
        ),
      ),
    );

    final poster = SizedBox(
      width: posterWidth,
      height: posterWidth * 1.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: t.shadowE1,
        ),
        child: NetworkCover(cover: a.coverImage),
      ),
    );

    final original = a.title.native ?? a.title.romaji;
    final d = details;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          a.title.preferred,
          style: compact
              ? AppText.title
              : AppText.headline.copyWith(fontSize: 30, height: 1.2),
        ),
        if (original != null && original != a.title.preferred)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(original, style: AppText.label.copyWith(color: t.fg2)),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (a.isAdult) const AdultBadge(),
            Text(
              d == null ? Fmt.posterCaption(a) : Fmt.titleMeta(d),
              style: AppText.body.copyWith(color: t.fg2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ScoreBlock(anime: a, details: d),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Symbols.play_arrow_rounded, fill: 1),
              label: Text(playLabel),
            ),
            StatusButton(mediaId: a.id),
            if (onTrailer case final onTrailer?)
              OutlinedButton.icon(
                onPressed: onTrailer,
                icon: const Icon(Symbols.movie_rounded, size: 18),
                label: const Text('Трейлер на YouTube'),
              )
            else if (trailerSearching)
              const TextButton(onPressed: null, child: Text('Ищем трейлер…'))
            else if (onFindTrailer case final onFind?)
              TextButton.icon(
                onPressed: onFind,
                icon: const Icon(Symbols.search_rounded, size: 18),
                label: const Text('Найти трейлер'),
              ),
            if (d?.siteUrl case final url?)
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                label: const Text('AniList'),
              ),
          ],
        ),
      ],
    );

    return Stack(
      children: [
        background,
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, compact ? 8 : 16, gutter, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (Navigator.of(context).canPop())
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: BackButton(),
                )
              else
                const SizedBox(height: 40),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [poster, const SizedBox(height: 16), info],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    poster,
                    const SizedBox(width: 32),
                    Expanded(child: info),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.anime, required this.details});

  final Anime anime;
  final AnimeDetails? details;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final score = anime.averageScore;
    final rank = details?.bestRatedRanking;
    Widget stat(String value, String label, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.scoreLg.copyWith(color: color ?? t.fg)),
        Text(label, style: AppText.caption.copyWith(color: t.fg2)),
      ],
    );
    return Wrap(
      spacing: 28,
      runSpacing: 12,
      children: [
        stat(
          score?.toString() ?? '—',
          'Рейтинг AniList',
          color: t.scoreColor(score),
        ),
        if (rank != null)
          stat(
            '#${rank.rank}',
            rank.season != null ? 'за сезон' : 'за всё время',
          ),
        if (anime.popularity case final p?) stat(Fmt.compact(p), 'в списках'),
      ],
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.duration,
    required this.watched,
    required this.isNext,
    required this.onToggle,
    this.onWatch,
  });

  final EpisodeInfo episode;

  /// Есть официальное видео серии — кнопка «Смотреть на YouTube».
  final VoidCallback? onWatch;
  final int? duration;
  final bool watched;

  /// Следующая к просмотру — выделена `accentSoft`.
  final bool isNext;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final e = episode;
    final color = e.aired ? t.fg : t.fg3;
    final trailing = e.aired
        ? (duration == null ? null : '$duration мин')
        : e.airingAt != null
        ? 'выйдет ${Fmt.dayMonth(e.airingAt!)}'
        : 'не вышла';
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isNext ? t.accentSoft : null,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${e.number}',
              style: AppText.labelStrong.copyWith(
                color: e.aired ? t.fg2 : t.fg3,
                fontFeatures: AppText.tabular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.title ?? 'Серия ${e.number}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(color: color),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: AppText.caption.copyWith(color: e.aired ? t.fg2 : t.fg3),
            ),
          if (onWatch != null)
            IconButton(
              tooltip: 'Смотреть на YouTube',
              onPressed: onWatch,
              icon: Icon(Symbols.smart_display_rounded, color: t.accent),
            ),
          SizedBox(
            width: 48,
            child: onToggle == null
                ? null
                : IconButton(
                    tooltip: watched
                        ? 'Снять отметку'
                        : 'Отметить просмотренной',
                    onPressed: onToggle,
                    icon: Icon(
                      watched
                          ? Symbols.check_circle_rounded
                          : Symbols.radio_button_unchecked_rounded,
                      fill: watched ? 1 : 0,
                      color: watched ? t.status[ListStatus.completed] : t.fg3,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.details});

  final AnimeDetails details;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _spoilers = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = widget.details;
    final a = d.anime;
    final text = d.plainDescription;
    final tags = d.tags.where((tag) => _spoilers || !tag.isSpoiler).toList();
    final hasSpoilers = d.tags.any((tag) => tag.isSpoiler);

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppText.overline.copyWith(color: t.fg2),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );

    final facts = <(String, String)>[
      if (d.studios.isNotEmpty)
        ('Студия', d.studios.map((s) => s.name).join(', ')),
      if (d.source != null) ('Источник', Fmt.sources[d.source] ?? d.source!),
      if (a.status != null)
        ('Статус', Fmt.releaseStatuses[a.status] ?? a.status!),
      if (d.startDate != null)
        (
          'Выход',
          [
            Fmt.fuzzyDate(d.startDate!),
            if (d.endDate != null &&
                d.endDate.toString() != d.startDate.toString())
              Fmt.fuzzyDate(d.endDate!),
          ].join(' — '),
        ),
      if (d.synonyms.isNotEmpty) ('Другие названия', d.synonyms.join(', ')),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text == null || text.isEmpty ? 'Описания на AniList нет.' : text,
            style: AppText.body.copyWith(color: text == null ? t.fg3 : t.fg),
          ),
          if (a.genres.isNotEmpty)
            section(
              'Жанры',
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in a.genres) Chip(label: Text(Fmt.genre(g))),
                ],
              ),
            ),
          if (facts.isNotEmpty)
            section(
              'Информация',
              Column(
                children: [
                  for (final (label, value) in facts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: Text(
                              label,
                              style: AppText.label.copyWith(color: t.fg2),
                            ),
                          ),
                          Expanded(child: Text(value, style: AppText.label)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (d.tags.isNotEmpty)
            section(
              'Теги',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        Chip(
                          label: Text(
                            tag.rank == null
                                ? tag.name
                                : '${tag.name} · ${tag.rank}%',
                          ),
                          side: tag.isSpoiler
                              ? BorderSide(color: t.warn)
                              : null,
                        ),
                    ],
                  ),
                  if (hasSpoilers)
                    TextButton(
                      onPressed: () => setState(() => _spoilers = !_spoilers),
                      child: Text(
                        _spoilers
                            ? 'Скрыть спойлеры'
                            : 'Показать теги-спойлеры',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.details, required this.width});

  final AnimeDetails details;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = details;
    Widget block(String title, String subtitle, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.title),
        const SizedBox(height: 4),
        Text(subtitle, style: AppText.caption.copyWith(color: t.fg2)),
        const SizedBox(height: 16),
        child,
      ],
    );

    final scores = d.scoreDistribution.isEmpty
        ? null
        : block(
            'Оценки пользователей AniList',
            'Число пользователей по баллам 10–100',
            ScoreHistogram(buckets: d.scoreDistribution),
          );
    final statuses = d.statusDistribution.isEmpty
        ? null
        : block(
            'Статусы в списках',
            'Списки пользователей AniList',
            StatusDistributionBar.fromBuckets(d.statusDistribution),
          );
    if (scores == null && statuses == null) {
      return const EmptyState(
        icon: Symbols.bar_chart_rounded,
        text: 'У AniList пока нет статистики по этому тайтлу',
      );
    }
    if (width >= AppLayout.expanded && scores != null && statuses != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: scores),
          const SizedBox(width: 48),
          Expanded(child: statuses),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?scores,
        if (scores != null && statuses != null) const SizedBox(height: 32),
        ?statuses,
      ],
    );
  }
}

class _Similar extends StatelessWidget {
  const _Similar({required this.details, required this.onOpenTitle});

  final AnimeDetails details;
  final ValueChanged<Anime> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = details;
    if (d.recommendations.isEmpty && d.relations.isEmpty) {
      return const EmptyState(
        icon: Symbols.recommend_rounded,
        text: 'Похожих тайтлов на AniList пока нет',
      );
    }

    Widget strip(List<Anime> items, {List<String>? labels}) => SizedBox(
      height: 168 * 1.5 + PosterCard.captionHeight + (labels == null ? 0 : 20),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) => SizedBox(
          width: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (labels != null)
                SizedBox(
                  height: 20,
                  child: Text(
                    labels[i],
                    style: AppText.caption.copyWith(color: t.accent),
                  ),
                ),
              Expanded(
                child: PosterCard(
                  anime: items[i],
                  onTap: () => onOpenTitle(items[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.recommendations.isNotEmpty) ...[
          Text('Рекомендации AniList', style: AppText.title),
          const SizedBox(height: 16),
          strip(d.recommendations),
        ],
        if (d.relations.isNotEmpty) ...[
          if (d.recommendations.isNotEmpty) const SizedBox(height: 32),
          Text('Связанные', style: AppText.title),
          const SizedBox(height: 16),
          strip(
            [for (final r in d.relations) r.anime],
            labels: [
              for (final r in d.relations)
                Fmt.relations[r.relationType] ?? r.relationType,
            ],
          ),
        ],
      ],
    );
  }
}
