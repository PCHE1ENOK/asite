import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/friends/friends_repository.dart';
import '../../data/github/github_exception.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
import '../app_scope.dart';
import '../format.dart';
import '../profiles/profile_widgets.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../widgets/verdict_visuals.dart';

/// Вкладки каталога друга.
enum FriendTab {
  watching('Смотрю'),
  completed('Просмотрено'),
  planning('В планах'),
  dropped('Брошено'),
  favorites('Понравилось'),
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

/// Каталог друга из его `anime-viewer-share.json` (только просмотр).
class FriendCatalogScreen extends StatefulWidget {
  const FriendCatalogScreen({super.key, required this.friend});

  final Friend friend;

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
        () => _error = switch (e.kind) {
          GitHubErrorKind.rateLimited => e.message,
          GitHubErrorKind.network =>
            'Не удалось связаться с GitHub. Проверьте подключение',
          _ => e.message,
        },
      );
    } on FormatException {
      if (mounted) setState(() => _error = 'Каталог друга повреждён');
    }
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
    return DefaultTabController(
      length: FriendTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              GitHubAvatar(url: f.avatarUrl, letter: f.login, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.login, style: AppText.labelStrong),
                    if (_catalog case final c? when c.updatedAt != null)
                      Text(
                        'обновлён ${Fmt.dayMonth(c.updatedAt!)}',
                        style: AppText.caption.copyWith(color: t.fg2),
                      ),
                  ],
                ),
              ),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final tab in FriendTab.values)
                Tab(
                  text: _catalog == null
                      ? tab.label
                      : '${tab.label} · '
                            '${titles.where(tab.matches).length}',
                ),
            ],
          ),
        ),
        body: switch ((_catalog, _error)) {
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
                _TabBody(tab: tab, titles: titles.where(tab.matches).toList()),
            ],
          ),
        },
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({required this.tab, required this.titles});

  final FriendTab tab;
  final List<FriendTitle> titles;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return EmptyState(
        icon: tab == FriendTab.notes
            ? Symbols.edit_note_rounded
            : Symbols.inbox_rounded,
        text: tab == FriendTab.notes ? 'Заметок нет' : 'В «${tab.label}» пусто',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = AppLayout.gutter(constraints.maxWidth);
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
          itemCount: titles.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _TitleRow(title: titles[i], showNote: tab == FriendTab.notes),
        );
      },
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.showNote});

  final FriendTitle title;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = title;
    final meta = [
      if (a.format != null) Fmt.formats[a.format] ?? a.format!,
      if (a.year != null) '${a.year}',
      if (a.status == ListStatus.current && a.episodes != null)
        '${a.progress} / ${a.episodes} эп.'
      else if (a.episodes != null)
        '${a.episodes} эп.',
    ].join(' · ');
    final note = a.note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: NetworkCover(url: a.cover, radius: AppRadius.sm),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.labelStrong.copyWith(color: t.fg),
              ),
              const SizedBox(height: 2),
              Text(meta, style: AppText.caption.copyWith(color: t.fg2)),
              if (a.score != null || a.favorite || a.adult) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    if (a.score case final s?)
                      Text(
                        '${s.toStringAsFixed(1).replaceAll('.', ',')} '
                        '${a.scoreSource == 'shikimori' ? 'Shiki' : 'AL'}',
                        style: AppText.caption.copyWith(
                          color: t.scoreColor(s),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (a.favorite)
                      Icon(
                        Symbols.favorite_rounded,
                        fill: 1,
                        size: 14,
                        color: t.bad,
                        semanticLabel: 'Понравилось',
                      ),
                    if (a.adult)
                      Text(
                        '18+',
                        style: AppText.caption.copyWith(color: t.bad),
                      ),
                  ],
                ),
              ],
              if (showNote && note != null) ...[
                const SizedBox(height: 8),
                _NoteView(note: note),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NoteView extends StatelessWidget {
  const _NoteView({required this.note});

  final FriendNote note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final verdict = switch (note.verdict) {
      'rewatch' => NoteVerdict.rewatch,
      'recommend' => NoteVerdict.recommend,
      'not' => NoteVerdict.notRecommend,
      _ => NoteVerdict.none,
    };
    final v = verdictVisual(verdict, t);
    final body = AppText.body.copyWith(color: t.fg);
    final label = AppText.label.copyWith(color: t.fg2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (verdict != NoteVerdict.none)
            Row(
              children: [
                Icon(v.icon, size: 16, color: v.color),
                const SizedBox(width: 6),
                Text(
                  v.label,
                  style: AppText.labelStrong.copyWith(color: v.color),
                ),
              ],
            ),
          // Текст из чужого файла — только как простой текст.
          if (note.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note.summary, style: body),
          ],
          if (note.liked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Понравилось: ${note.liked.join(', ')}', style: label),
          ],
          if (note.dropReasons.isNotEmpty || note.dropText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Бросил: ${[...note.dropReasons, if (note.dropText.isNotEmpty) note.dropText].join(', ')}',
              style: label,
            ),
          ],
          for (final (episode, time, text) in note.moments) ...[
            const SizedBox(height: 6),
            Text(
              'Серия $episode${time == null ? '' : ' · $time'} — $text',
              style: label,
            ),
          ],
        ],
      ),
    );
  }
}
