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

/// Комментарии к официальным роликам YouTube (design/screens.md §13):
/// только чтение. Текст — простой текст: без HTML и активных ссылок.
/// В карточке тайтла — вкладка, в плеере — панель под видео.
class CommentsTab extends StatefulWidget {
  const CommentsTab({super.key, required this.videos});

  /// Ролики тайтла (не пустой список); в плеере — один текущий.
  final List<EmbeddedVideo> videos;

  /// Подпись источника, обязательна под комментариями.
  static const attribution = 'Комментарии — с YouTube';

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

  void _setOrder(CommentOrder order) {
    if (order == _order) return;
    setState(() => _order = order);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = _status;

    Widget message(String text, {Widget? action}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppText.body.copyWith(color: t.fg2)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );

    final openVideo = TextButton.icon(
      onPressed: () => openExternally(context, _video.watchUrl),
      icon: const Icon(Symbols.open_in_new_rounded, size: 18),
      label: const Text('Открыть на YouTube'),
    );

    final Widget body;
    if (_comments.isEmpty && _loading) {
      body = Column(
        children: [for (var i = 0; i < 4; i++) const _CommentSkeleton()],
      );
    } else if (status is CommentsDisabled) {
      body = message(
        'Комментарии отключены для этого видео. Так решил правообладатель '
        'на YouTube',
      );
    } else if (status is CommentsFailed && _comments.isEmpty) {
      body = message(
        'Не удалось загрузить комментарии. Проверьте подключение к интернету',
        action: OutlinedButton(
          onPressed: _reload,
          child: const Text('Повторить'),
        ),
      );
    } else if (_comments.isEmpty) {
      body = message(
        'Комментариев пока нет. Будьте первым — комментарии пишутся '
        'на YouTube',
        action: openVideo,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in _comments)
            _CommentTile(
              key: ValueKey(c.id),
              comment: c,
              videoId: _video.videoId,
            ),
          if (status is CommentsFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Не удалось загрузить комментарии. Проверьте подключение к интернету',
                style: AppText.label.copyWith(color: t.bad),
              ),
            ),
          if (_next != null || status is CommentsFailed)
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
              label: Text(_loading ? 'Загружаем…' : 'Показать ещё'),
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
              Text(
                _comments.isEmpty
                    ? 'Комментарии'
                    : 'Комментарии · ${Fmt.thousands(_comments.length)}',
                style: AppText.title,
              ),
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
            ],
          ),
          const SizedBox(height: 16),
          body,
          const SizedBox(height: 16),
          Text(
            CommentsTab.attribution,
            style: AppText.caption.copyWith(color: t.fg3),
          ),
        ],
      ),
    );
  }

  static String _videoLabel(EmbeddedVideo v) =>
      v.episode == null ? v.title : 'Серия ${v.episode}';
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({super.key, required this.comment, required this.videoId});

  final YouTubeComment comment;
  final String videoId;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _expanded = false;

  static const maxLines = 4;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = widget.comment;
    final avatar = c.authorAvatar;
    final style = AppText.body.copyWith(color: t.fg);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: t.accentSoft,
            foregroundImage: avatar == null
                ? null
                : AppScope.of(context).imageResolver(avatar),
            child: Text(
              c.author.characters.firstOrNull?.toUpperCase() ?? '?',
              style: AppText.labelStrong.copyWith(color: t.accent),
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
                      TextSpan(
                        text: c.author,
                        style: AppText.labelStrong.copyWith(color: t.fg),
                      ),
                      TextSpan(
                        text: '  ${Fmt.relative(c.publishedAt)}',
                        style: AppText.caption.copyWith(color: t.fg3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Простой текст: разметка не выполняется, ссылки не активны.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final painter = TextPainter(
                      text: TextSpan(text: c.text, style: style),
                      maxLines: maxLines,
                      textDirection: Directionality.of(context),
                    )..layout(maxWidth: constraints.maxWidth);
                    final long = painter.didExceedMaxLines;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.text,
                          style: style,
                          maxLines: _expanded ? null : maxLines,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                        ),
                        if (long)
                          TextButton(
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            child: Text(_expanded ? 'Свернуть' : 'Ещё'),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Symbols.thumb_up_rounded, size: 14, color: t.fg3),
                    const SizedBox(width: 4),
                    Text(
                      Fmt.thousands(c.likes),
                      style: AppText.caption.copyWith(color: t.fg2),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () =>
                          openExternally(context, c.urlFor(widget.videoId)),
                      icon: const Icon(Symbols.open_in_new_rounded, size: 16),
                      label: const Text('Открыть на YouTube'),
                    ),
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

class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeleton(width: 36, height: 36, radius: 18),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: 0.3,
                child: Skeleton(height: 12),
              ),
              SizedBox(height: 8),
              Skeleton(height: 12),
              SizedBox(height: 6),
              FractionallySizedBox(
                widthFactor: 0.7,
                child: Skeleton(height: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
