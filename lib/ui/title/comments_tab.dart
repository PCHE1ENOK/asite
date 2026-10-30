import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/sources/video_source.dart';
import '../../data/sources/youtube_comments.dart';
import '../app_scope.dart';
import '../format.dart';
import '../player/youtube_player_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/filter_controls.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Вкладка «Комментарии» к официальным роликам YouTube тайтла.
///
/// Текст комментариев показывается как простой текст: без HTML и без
/// активных ссылок.
class CommentsTab extends StatefulWidget {
  const CommentsTab({super.key, required this.videos});

  /// Ролики тайтла (не пустой список).
  final List<EmbeddedVideo> videos;

  @override
  State<CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<CommentsTab> {
  late EmbeddedVideo _video = widget.videos.first;
  CommentOrder _order = CommentOrder.relevance;
  final List<YouTubeComment> _comments = [];
  String? _next;
  CommentsResult? _status;
  bool _loading = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status == null && !_loading) _reload();
  }

  void _reload() {
    _comments.clear();
    _next = null;
    _status = null;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    final r = await AppScope.of(context).services.comments
        .fetch(_video.videoId, order: _order, pageToken: _next);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _status = r;
      if (r is CommentsLoaded) {
        _comments.addAll(r.page.comments);
        _next = r.page.nextPageToken;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = _status;
    final Widget body;
    if (_comments.isEmpty && _loading) {
      body = Column(
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Skeleton(height: 64),
            ),
        ],
      );
    } else if (status is CommentsDisabled) {
      body = const EmptyState(
        icon: Symbols.comments_disabled_rounded,
        text: 'Комментарии отключены для этого видео',
      );
    } else if (status is CommentsFailed && _comments.isEmpty) {
      body = ErrorState(
        message: 'Не удалось загрузить комментарии',
        hint: status.reason,
        onRetry: _reload,
      );
    } else if (_comments.isEmpty) {
      body = const EmptyState(
        icon: Symbols.chat_bubble_rounded,
        text: 'Комментариев пока нет',
      );
    } else {
      body = Column(
        children: [
          for (final c in _comments) _CommentTile(comment: c),
          if (status is CommentsFailed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Не удалось загрузить',
                style: AppText.label.copyWith(color: t.bad),
              ),
            ),
          if (_next != null || status is CommentsFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _loading ? null : _load,
                child: Text(_loading ? 'Загрузка…' : 'Показать ещё'),
              ),
            ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.videos.length > 1)
                PillMenu<EmbeddedVideo>(
                  label: _videoLabel(_video),
                  items: widget.videos,
                  value: _video,
                  itemLabel: _videoLabel,
                  onSelected: (v) {
                    setState(() => _video = v);
                    _reload();
                  },
                ),
              PillButton(
                label: 'По популярности',
                selected: _order == CommentOrder.relevance,
                onPressed: () => _setOrder(CommentOrder.relevance),
              ),
              PillButton(
                label: 'По времени',
                selected: _order == CommentOrder.time,
                onPressed: () => _setOrder(CommentOrder.time),
              ),
              TextButton.icon(
                onPressed: () => openExternally(context, _video.watchUrl),
                icon: const Icon(Symbols.open_in_new_rounded, size: 18),
                label: const Text('Открыть на YouTube'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Комментарии с YouTube · ${_video.channel}',
            style: AppText.caption.copyWith(color: t.fg3),
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  void _setOrder(CommentOrder order) {
    if (order == _order) return;
    setState(() => _order = order);
    _reload();
  }

  static String _videoLabel(EmbeddedVideo v) =>
      v.episode == null ? v.title : 'Серия ${v.episode}';
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final YouTubeComment comment;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = comment;
    final avatar = c.authorAvatar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: t.surface3,
            foregroundImage: avatar == null
                ? null
                : AppScope.of(context).imageResolver(avatar),
            child: Text(
              c.author.characters.firstOrNull?.toUpperCase() ?? '?',
              style: AppText.labelStrong,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: c.author, style: AppText.labelStrong),
                      TextSpan(
                        text:
                            '  ${Fmt.dayMonth(c.publishedAt)} ${c.publishedAt.toLocal().year}',
                        style: AppText.caption.copyWith(color: t.fg3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Простой текст: разметка не выполняется, ссылки не активны.
                SelectableText(c.text, style: AppText.body),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Symbols.thumb_up_rounded, size: 14, color: t.fg3),
                    const SizedBox(width: 4),
                    Text(
                      Fmt.thousands(c.likes),
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                    if (c.replies > 0) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${c.replies} ${Fmt.plural(c.replies, 'ответ', 'ответа', 'ответов')}',
                        style: AppText.caption.copyWith(color: t.fg3),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
