import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/friends/friends_repository.dart';
import '../../data/github/github_exception.dart';
import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/score.dart';
import '../../data/models/title_note.dart';
import '../app_scope.dart';
import '../format.dart';
import '../profiles/profile_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/badges.dart';
import '../widgets/cover_image.dart';
import '../widgets/favorite_button.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../widgets/status_widgets.dart';
import '../widgets/toast.dart';
import '../widgets/verdict_visuals.dart';

/// Вкладки каталога друга.
enum FriendTab {
  watching('Смотрю'),
  completed('Просмотрено'),
  planning('В планах'),
  dropped('Брошено'),
  favorites('♥ Понравилось'),
  notes('Заметки');

  const FriendTab(this.label);

  final String label;

  bool matches(FriendTitle t) => switch (this) {
    watching =>
      t.status == ListStatus.current || t.status == ListStatus.repeating,
    completed => t.status == ListStatus.completed,
    planning => t.status == ListStatus.planning,
    dropped => t.status == ListStatus.dropped,
    favorites => t.favorite,
    notes => t.note != null && !t.note!.isEmpty,
  };
}

/// Тайтл друга как [Anime] — для постера, сердца и карточки тайтла.
Anime animeOf(FriendTitle t) => Anime(
  id: t.id,
  title: AnimeTitle(english: t.english ?? t.title, romaji: t.romaji),
  coverImage: CoverImage(large: t.cover),
  format: t.format,
  seasonYear: t.year,
  episodes: t.episodes,
  isAdult: t.adult,
);

/// Каталог друга (design/screens.md §19.2): только просмотр.
class FriendCatalogScreen extends StatefulWidget {
  const FriendCatalogScreen({
    super.key,
    required this.friend,
    required this.onOpenTitle,
  });

  final Friend friend;
  final ValueChanged<Anime> onOpenTitle;

  @override
  State<FriendCatalogScreen> createState() => _FriendCatalogScreenState();
}

class _FriendCatalogScreenState extends State<FriendCatalogScreen> {
  FriendCatalog? _catalog;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final c = await AppScope.of(context).services.friends
          .catalog(widget.friend.login, force: force);
      if (mounted) setState(() => _catalog = c);
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.kind == GitHubErrorKind.network
            ? 'Не удалось связаться с GitHub. Проверьте подключение'
            : e.message,
      );
    } on FormatException {
      if (mounted) setState(() => _error = 'Каталог друга повреждён');
    }
  }

  String get _name {
    final owner = _catalog?.owner;
    return owner == null || owner.isEmpty ? widget.friend.displayName : owner;
  }

  Future<void> _remove() async {
    final f = widget.friend;
    final name = _name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = context.tokens;
        return AlertDialog(
          backgroundColor: t.surface2,
          title: Text('Удалить $name из друзей?', style: AppText.title),
          content: Text(
            'Каталог @${f.login} пропадёт из вашего списка друзей. У $name '
            'ничего не изменится, и вы сможете снова найти его по нику.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: t.bad),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить из друзей'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final friends = AppScope.of(context).services.friends;
    final messenger = ScaffoldMessenger.of(context);
    await friends.remove(f.login);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showToast(
      '$name удалён из друзей',
      actionLabel: 'Отменить',
      onAction: () => friends.restore(f),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = widget.friend;
    final showAdult = AppScope.of(context).settings.showAdult;
    final titles = [
      for (final title in _catalog?.titles ?? const <FriendTitle>[])
        if (showAdult || !title.adult) title,
    ];
    final compact = MediaQuery.sizeOf(context).width < AppLayout.medium;
    final removeButton = OutlinedButton.icon(
      onPressed: _remove,
      icon: const Icon(Symbols.person_remove_rounded, size: 18),
      label: const Text('Удалить из друзей'),
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 8, compact ? 16 : 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GitHubAvatar(url: f.avatarUrl, letter: _name, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Каталог $_name',
                      style: (compact ? AppText.title : AppText.headline)
                          .copyWith(color: t.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '@${f.login}',
                        if (_catalog?.updatedAt case final at?)
                          'обновлено ${Fmt.relative(at)}',
                        'только просмотр',
                      ].join(' · '),
                      style: AppText.label.copyWith(color: t.fg2),
                    ),
                  ],
                ),
              ),
              if (!compact) removeButton,
            ],
          ),
          if (compact) ...[const SizedBox(height: 12), removeButton],
        ],
      ),
    );
    return DefaultTabController(
      length: FriendTab.values.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('Друзья')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final tab in FriendTab.values)
                  Tab(
                    text: _catalog == null
                        ? tab.label
                        : '${tab.label} · ${titles.where(tab.matches).length}',
                  ),
              ],
            ),
            Expanded(
              child: switch ((_catalog, _error)) {
                (_, final error?) => ErrorState(
                  message: error,
                  onRetry: () => _load(force: true),
                ),
                (null, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Skeleton(height: 72),
                      SizedBox(height: 12),
                      Skeleton(height: 72),
                    ],
                  ),
                ),
                (final _?, _) => TabBarView(
                  children: [
                    for (final tab in FriendTab.values)
                      _TabBody(
                        tab: tab,
                        titles: titles.where(tab.matches).toList(),
                        onOpenTitle: widget.onOpenTitle,
                      ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.tab,
    required this.titles,
    required this.onOpenTitle,
  });

  final FriendTab tab;
  final List<FriendTitle> titles;
  final ValueChanged<Anime> onOpenTitle;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return EmptyState(
        icon: tab == FriendTab.notes
            ? Symbols.edit_note_rounded
            : Symbols.inbox_rounded,
        text: tab == FriendTab.notes ? 'Заметок нет' : 'Здесь пока пусто',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = AppLayout.gutter(width);
        if (tab == FriendTab.notes) {
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
            itemCount: titles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _NoteCard(
              title: titles[i],
              onTap: () => onOpenTitle(animeOf(titles[i])),
            ),
          );
        }
        // Сетка постеров как в каталоге: 148–220, 2:3.
        final inner = width - gutter * 2;
        final gap = AppLayout.posterGap(width);
        final cols = ((inner + gap) / (AppLayout.posterMin + gap))
            .floor()
            .clamp(2, 10);
        final itemWidth = (inner - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
          child: Wrap(
            spacing: gap,
            runSpacing: 20,
            children: [
              for (final title in titles)
                SizedBox(
                  width: itemWidth,
                  child: _FriendPoster(
                    title: title,
                    onTap: () => onOpenTitle(animeOf(title)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Постер тайтла друга: оценка, статус и прогресс **друга**; сердце —
/// **ваше** «Понравилось».
class _FriendPoster extends StatelessWidget {
  const _FriendPoster({required this.title, required this.onTap});

  final FriendTitle title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = title;
    final score = a.score == null
        ? null
        : Score10(
            a.score!,
            a.scoreSource == 'shikimori'
                ? ScoreSource.shikimori
                : ScoreSource.anilist,
          );
    final caption = [
      if (a.format != null) Fmt.formats[a.format] ?? a.format!,
      if (a.year != null) '${a.year}',
      if (a.status == ListStatus.current || a.status == ListStatus.repeating)
        '${a.progress} / ${a.episodes ?? '?'} эп.'
      else if (a.episodes != null)
        '${a.episodes} эп.',
    ].join(' · ');
    return Semantics(
      button: true,
      label: [
        a.title,
        if (a.status case final s?) 'у друга: ${Fmt.status(s)}',
      ].join(', '),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkCover(url: a.cover),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ScoreBadge(score: score, onPoster: true),
                        if (a.adult) ...[
                          const SizedBox(height: 4),
                          const AdultBadge(),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Column(
                      children: [
                        if (a.status case final s?) ...[
                          ListStatusDot(status: s),
                          const SizedBox(height: 6),
                        ],
                        FavoriteButton(anime: animeOf(a), onPoster: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.labelStrong.copyWith(color: t.fg),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
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

/// Заметка друга: обложка 64, название, вердикт-чип, итог, моменты.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.onTap});

  final FriendTitle title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final note = title.note!;
    final verdict = switch (note.verdict) {
      'rewatch' => NoteVerdict.rewatch,
      'recommend' => NoteVerdict.recommend,
      'not' => NoteVerdict.notRecommend,
      _ => NoteVerdict.none,
    };
    final v = verdictVisual(verdict, t);
    final body = AppText.body.copyWith(color: t.fg);
    final label = AppText.label.copyWith(color: t.fg2);
    return Material(
      color: t.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: NetworkCover(url: title.cover, radius: AppRadius.sm),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.title,
                      style: AppText.labelStrong.copyWith(color: t.fg),
                    ),
                    if (verdict != NoteVerdict.none) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: v.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(v.icon, size: 14, color: v.color),
                            const SizedBox(width: 4),
                            Text(
                              v.label,
                              style: AppText.caption.copyWith(
                                color: v.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Тексты чужого файла — только как простой текст.
                    if (note.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(note.summary, style: body),
                    ],
                    if (note.liked.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Понравилось: ${note.liked.join(', ')}',
                        style: label,
                      ),
                    ],
                    if (note.dropReasons.isNotEmpty ||
                        note.dropText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Бросил: ${[...note.dropReasons, if (note.dropText.isNotEmpty) note.dropText].join(', ')}',
                        style: label,
                      ),
                    ],
                    for (final (episode, time, text) in note.moments) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$episode эп.${time == null ? '' : ' · $time'} $text',
                        style: label,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
