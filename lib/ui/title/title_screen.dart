import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/anilist/anilist_client.dart';
import '../../data/anime_repository.dart';
import '../../data/models/anime.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import '../widgets/cover_image.dart';
import '../widgets/poster_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import 'episode_list.dart';
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
  similar('Похожие');

  const TitleTab(this.label);

  final String label;
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: TitleTab.values.length, vsync: this);
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
    } on AniListException catch (e) {
      if (mounted) setState(() => _error = e);
    }
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
            listenable: _tabs,
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    anime: anime,
                    details: details,
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabs: [
                        for (final t in TitleTab.values) Tab(text: t.label),
                      ],
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
    return switch (TitleTab.values[_tabs.index]) {
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
    return [
      SliverPadding(
        padding: pad,
        sliver: SliverList.builder(
          itemCount: episodes.length,
          itemBuilder: (context, i) =>
              _EpisodeRow(episode: episodes[i], duration: duration),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.anime,
    required this.details,
    required this.width,
    required this.gutter,
  });

  final Anime anime;
  final AnimeDetails? details;
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
              : a.coverImage.best == null
              ? const SizedBox.shrink()
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Image(
                    image: resolver(a.coverImage.best!),
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
        child: NetworkCover(url: a.coverImage.best, color: a.coverImage.color),
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
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Источники видео ещё не подключены'),
                ),
              ),
              icon: const Icon(Symbols.play_arrow_rounded, fill: 1),
              label: const Text('Начать просмотр'),
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
  const _EpisodeRow({required this.episode, required this.duration});

  final EpisodeInfo episode;
  final int? duration;

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
        border: Border(bottom: BorderSide(color: t.border)),
      ),
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
            StatusDistributionBar(buckets: d.statusDistribution),
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
