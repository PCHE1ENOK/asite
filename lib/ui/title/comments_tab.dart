import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/sources/video_source.dart';
import '../../data/sources/youtube_comments.dart';
import '../../data/translation/translation.dart';
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

  /// Ждём ответа на плашку MyMemory (ПК).
  Completer<bool>? _consent;

  /// Перед первым переводом на сервере — плашка над списком; ответ
  /// «Понятно» запоминается в настройках устройства.
  Future<bool> _ensureConsent() async {
    final services = AppScope.of(context).services;
    if (services.translator.server == null) return true;
    if (await services.preferences.myMemoryConsent()) return true;
    if (!mounted) return false;
    if (_consent == null) setState(() => _consent = Completer<bool>());
    return _consent!.future;
  }

  Future<void> _answerConsent(bool ok) async {
    final c = _consent;
    if (c == null) return;
    if (ok) {
      await AppScope.of(context).services.preferences.setMyMemoryConsent(true);
    }
    if (!mounted) return;
    setState(() => _consent = null);
    c.complete(ok);
  }

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
              ensureConsent: _ensureConsent,
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
          if (_consent != null) _consentBanner(context),
          body,
          const SizedBox(height: 16),
          Text(
            AppScope.of(context).services.translator.server == null
                ? '${CommentsTab.attribution} · перевод выполняется на устройстве'
                : CommentsTab.attribution,
            style: AppText.caption.copyWith(color: t.fg3),
          ),
        ],
      ),
    );
  }

  Widget _consentBanner(BuildContext context) {
    final t = context.tokens;
    final server = AppScope.of(context).services.translator.server;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: t.surface2,
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
              Icon(Symbols.lock_rounded, size: 18, color: t.fg2),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Текст комментария отправляется на сервер $server '
                  'для перевода',
                  style: AppText.body,
                ),
              ),
            ],
          ),
          FilledButton(
            onPressed: () => _answerConsent(true),
            child: const Text('Понятно'),
          ),
          TextButton(
            onPressed: () => _answerConsent(false),
            child: const Text('Не переводить'),
          ),
        ],
      ),
    );
  }

  static String _videoLabel(EmbeddedVideo v) =>
      v.episode == null ? v.title : 'Серия ${v.episode}';
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.videoId,
    required this.ensureConsent,
  });

  final YouTubeComment comment;
  final String videoId;

  /// Согласие на отправку текста на сервер перевода.
  final Future<bool> Function() ensureConsent;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

/// Этап перевода комментария (design/screens.md §13.1).
enum _Tr { idle, translating, needPack, downloading, done, quota, error }

class _CommentTileState extends State<_CommentTile> {
  bool _expanded = false;

  /// Кнопка «Перевести на русский»: `null` — язык ещё определяем.
  bool? _canTranslate;
  String? _lang;
  var _tr = _Tr.idle;
  String? _translation;
  bool _showOriginal = false;
  String? _error;
  bool _started = false;

  static const maxLines = 4;

  CommentTranslator get _translator => AppScope.of(context).services.translator;

  String get _text => widget.comment.text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final translator = _translator;
    _translation = translator.cached(_text);
    if (_translation != null) _tr = _Tr.done;
    _lang = translator.knownLanguage(_text);
    translator.canTranslate(_text).then((v) {
      if (mounted) {
        setState(() {
          _canTranslate = v;
          _lang = translator.knownLanguage(_text);
        });
      }
    });
  }

  Future<void> _translate() async {
    if (!await widget.ensureConsent() || !mounted) return;
    final translator = _translator;
    if (await translator.needsPack(_text)) {
      if (mounted) setState(() => _tr = _Tr.needPack);
      return;
    }
    await _run();
  }

  Future<void> _download() async {
    setState(() => _tr = _Tr.downloading);
    final ok = await _translator.downloadPack(_text);
    if (!mounted) return;
    if (ok) {
      await _run();
    } else {
      setState(() {
        _tr = _Tr.error;
        _error = 'Не удалось скачать языковой пакет: нет сети';
      });
    }
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _tr = _Tr.translating;
      _error = null;
    });
    final r = await _translator.translate(_text);
    if (!mounted) return;
    setState(() {
      switch (r) {
        case Translated(:final text):
          _translation = text;
          _showOriginal = false;
          _tr = _Tr.done;
        case TranslationQuotaExceeded():
          _tr = _Tr.quota;
        case TranslationFailed(:final message):
          _tr = _Tr.error;
          _error = message;
      }
    });
  }

  Widget _expandable(String text, TextStyle style) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: maxLines,
        textDirection: Directionality.of(context),
      )..layout(maxWidth: constraints.maxWidth);
      final long = painter.didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: style,
            maxLines: _expanded ? null : maxLines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
          if (long)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Свернуть' : 'Ещё'),
            ),
        ],
      );
    },
  );

  Widget _box(List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.tokens.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  /// Текст комментария и блок перевода под ним.
  Widget _body(BuildContext context, TextStyle style) {
    final t = context.tokens;
    final from = languageFrom(_lang);
    final server = _translator.server;
    final translation = _translation;
    final hideOriginal = _tr == _Tr.done && !_showOriginal;
    final Widget? below = switch (_tr) {
      _Tr.idle when _canTranslate ?? false => TextButton.icon(
        onPressed: _translate,
        icon: const Icon(Symbols.translate_rounded, size: 16),
        label: const Text('Перевести на русский'),
      ),
      _Tr.idle => null,
      _Tr.translating => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(height: 12),
            const SizedBox(height: 6),
            const FractionallySizedBox(
              widthFactor: 0.6,
              child: Skeleton(height: 12),
            ),
            const SizedBox(height: 8),
            Text(
              from == null ? 'Переводим…' : 'Переводим $from…',
              style: AppText.caption.copyWith(color: t.fg2),
            ),
          ],
        ),
      ),
      _Tr.needPack => _box([
        Text(
          'Для перевода ${from ?? ''} нужен языковой пакет на устройстве '
                  '(≈ 30 МБ). Перевод выполняется на устройстве, текст '
                  'никуда не отправляется'
              .replaceAll('  ', ' '),
          style: AppText.label.copyWith(color: t.fg2),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _download,
          icon: const Icon(Symbols.cloud_download_rounded, size: 18),
          label: const Text('Скачать пакет перевода'),
        ),
      ]),
      _Tr.downloading => _box([
        Text(
          languageTag(_lang) == null
              ? 'Скачиваем языковой пакет'
              : 'Скачиваем пакет «${languageTag(_lang)} → рус.»',
          style: AppText.label.copyWith(color: t.fg2),
        ),
        const SizedBox(height: 8),
        // ML Kit не сообщает процент — прогресс без числа.
        const LinearProgressIndicator(),
      ]),
      _Tr.done => _box([
        Text(
          [
            from == null ? 'Перевод' : 'Перевод $from',
            server ?? 'на устройстве',
          ].join(' · '),
          style: AppText.caption.copyWith(color: t.fg3),
        ),
        const SizedBox(height: 4),
        _expandable(translation ?? '', style),
        TextButton(
          onPressed: () => setState(() => _showOriginal = !_showOriginal),
          child: Text(_showOriginal ? 'Скрыть оригинал' : 'Показать оригинал'),
        ),
      ]),
      _Tr.quota => _box([
        Row(
          children: [
            Icon(Symbols.pause_circle_rounded, size: 18, color: t.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Лимит перевода исчерпан, попробуйте завтра',
                style: AppText.label.copyWith(color: t.warn),
              ),
            ),
          ],
        ),
      ]),
      _Tr.error => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _error ?? translationOfflineMessage,
              style: AppText.label.copyWith(color: t.bad),
            ),
            TextButton(onPressed: _translate, child: const Text('Повторить')),
          ],
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Простой текст: разметка не выполняется, ссылки не активны.
        if (!hideOriginal) _expandable(_text, style),
        ?below,
      ],
    );
  }

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
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      c.author,
                      style: AppText.labelStrong.copyWith(color: t.fg),
                    ),
                    Text(
                      Fmt.relative(c.publishedAt),
                      style: AppText.caption.copyWith(color: t.fg3),
                    ),
                    if (_lang != 'ru')
                      if (languageTag(_lang) case final tag?)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: t.surface2,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            tag,
                            style: AppText.caption.copyWith(color: t.fg2),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 4),
                _body(context, style),
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
