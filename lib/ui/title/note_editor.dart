import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
import '../../data/notes/notes_repository.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/filter_controls.dart';
import '../widgets/verdict_visuals.dart';
import 'episode_list.dart';

/// Блок «Моя заметка» на карточке тайтла — между шапкой и вкладками
/// (design/screens.md §12).
class NoteBlock extends StatefulWidget {
  const NoteBlock({super.key, required this.details, required this.width});

  final AnimeDetails details;
  final double width;

  @override
  State<NoteBlock> createState() => _NoteBlockState();
}

class _NoteBlockState extends State<NoteBlock> {
  /// Подписка живёт, пока жив блок: перестроения (смена вкладки) не
  /// сбрасывают её в «загрузку».
  Stream<TitleNote?>? _stream;
  NotesRepository? _repo;

  AnimeDetails get details => widget.details;
  double get width => widget.width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppScope.of(context).services.notes;
    if (!identical(repo, _repo)) {
      _repo = repo;
      _stream = repo.watchNote(details.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = context.tokens;
    final dropped = scope.library[details.id]?.status == ListStatus.dropped;
    return StreamBuilder<TitleNote?>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final n = snap.data;
        final compact = width < AppLayout.medium;
        final head = Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Моя заметка', style: AppText.bodyStrong),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.lock_rounded, size: 14, color: t.fg3),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'видна только в профиле «${scope.services.profile.name}»',
                    style: AppText.caption.copyWith(color: t.fg3),
                  ),
                ),
              ],
            ),
          ],
        );
        final Widget body;
        final Widget action;
        if (n == null) {
          body = Text(
            dropped
                ? 'Записать, почему бросили'
                : 'Записать, почему бросили или что понравилось',
            style: AppText.body.copyWith(color: t.fg2),
          );
          action = FilledButton.tonalIcon(
            onPressed: () => openNoteEditor(context, details),
            icon: const Icon(Symbols.edit_rounded, size: 18),
            label: const Text('Добавить заметку'),
          );
        } else {
          final v = verdictVisual(n.verdict, t);
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(v.icon, size: 18, color: v.color),
                  const SizedBox(width: 6),
                  Text(
                    v.label,
                    style: AppText.labelStrong.copyWith(color: v.color),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                n.summary.isEmpty ? 'Без итога' : n.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  color: n.summary.isEmpty ? t.fg3 : t.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                noteMeta(n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: t.fg2),
              ),
            ],
          );
          action = OutlinedButton.icon(
            onPressed: () => openNoteEditor(context, details),
            icon: const Icon(Symbols.edit_rounded, size: 18),
            label: const Text('Редактировать'),
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface1,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              const SizedBox(height: 10),
              if (compact) ...[
                body,
                const SizedBox(height: 12),
                action,
              ] else
                Row(
                  crossAxisAlignment: n == null
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(child: body),
                    const SizedBox(width: 16),
                    action,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// «2 момента · причина: Затянуто · обновлено 3 дня назад».
  static String noteMeta(TitleNote n, {DateTime? now}) {
    final reason = n.dropReasons.isNotEmpty
        ? n.dropReasons.join(', ')
        : n.dropText.trim();
    return [
      if (n.moments.isNotEmpty)
        '${n.moments.length} ${Fmt.plural(n.moments.length, 'момент', 'момента', 'моментов')}',
      if (reason.isNotEmpty) 'причина: $reason',
      'обновлено ${Fmt.relative(n.updatedAt.toLocal(), now: now)}',
    ].join(' · ');
  }
}

/// Открывает редактор: на ПК — панель справа поверх затемнения,
/// на телефоне — отдельный экран.
Future<void> openNoteEditor(BuildContext context, AnimeDetails details) {
  final scope = AppScope.of(context);
  final entry = scope.library[details.id];
  Widget editor() => NoteEditorPanel(
    details: details,
    notes: scope.services.notes,
    profileName: scope.services.profile.name,
    status: entry?.status,
    progress: entry?.progress ?? 0,
  );
  final phone = MediaQuery.sizeOf(context).width < AppLayout.medium;
  if (phone) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => Material(child: editor())));
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: math.min(480, MediaQuery.sizeOf(context).width),
        height: double.infinity,
        child: Material(
          color: context.tokens.surface1,
          elevation: 12,
          child: editor(),
        ),
      ),
    ),
    transitionBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

enum _SaveState { idle, saving, error }

/// Редактор заметки. Сохраняет только по «Сохранить»; при выходе
/// с изменениями спрашивает, что с ними делать.
class NoteEditorPanel extends StatefulWidget {
  const NoteEditorPanel({
    super.key,
    required this.details,
    required this.notes,
    required this.profileName,
    this.status,
    this.progress = 0,
  });

  final AnimeDetails details;
  final NotesRepository notes;
  final String profileName;
  final ListStatus? status;
  final int progress;

  @override
  State<NoteEditorPanel> createState() => _NoteEditorPanelState();
}

class _NoteEditorPanelState extends State<NoteEditorPanel> {
  final _summary = TextEditingController();
  final _liked = TextEditingController();
  final _dropText = TextEditingController();
  final _momentTime = TextEditingController();
  final _momentText = TextEditingController();
  final _momentTextFocus = FocusNode();

  var _reasons = <String>[];
  var _verdict = NoteVerdict.none;
  var _moments = <NoteMoment>[];
  late int _momentEpisode;
  String? _momentError;

  /// Сохранённая заметка (`null` — новая).
  TitleNote? _saved;
  bool _loaded = false;
  var _state = _SaveState.idle;

  int get _id => widget.details.id;

  /// Число серий для выбора момента.
  int get _episodeCount {
    final known = buildEpisodes(widget.details).length;
    return math.max(known, math.max(widget.progress, 1));
  }

  /// Длительность серии в минутах (для проверки таймкода).
  int get _episodeMinutes => widget.details.anime.duration ?? 60;

  @override
  void initState() {
    super.initState();
    _momentEpisode = math.min(widget.progress + 1, _episodeCount);
    for (final c in [_summary, _liked, _dropText]) {
      c.addListener(_changed);
    }
    _load();
  }

  Future<void> _load() async {
    final n = await widget.notes.note(_id);
    if (!mounted) return;
    setState(() {
      _saved = n;
      _fill(n);
      _loaded = true;
    });
  }

  void _fill(TitleNote? n) {
    _summary.text = n?.summary ?? '';
    _liked.text = n?.liked ?? '';
    _dropText.text = n?.dropText ?? '';
    _reasons = [...?n?.dropReasons];
    _verdict = n?.verdict ?? NoteVerdict.none;
    _moments = [...?n?.moments];
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [_summary, _liked, _dropText, _momentTime, _momentText]) {
      c.dispose();
    }
    _momentTextFocus.dispose();
    super.dispose();
  }

  TitleNote _draft() => TitleNote(
    mediaId: _id,
    updatedAt: DateTime.now(),
    summary: _summary.text,
    verdict: _verdict,
    liked: _liked.text,
    dropReasons: _reasons,
    dropText: _dropText.text,
    moments: _moments,
  );

  /// Содержимое без служебных полей — для сравнения с сохранённым.
  static String _content(TitleNote? n) {
    if (n == null || n.isEmpty) return '';
    final j = n.toJson()
      ..remove('updatedAt')
      ..remove('deleted');
    for (final k in ['summary', 'liked', 'dropText']) {
      if (j[k] case final String s) j[k] = s.trim();
    }
    j.removeWhere((_, v) => v == '');
    return jsonEncode(j);
  }

  bool get _dirty => _loaded && _content(_draft()) != _content(_saved);

  Future<bool> _save() async {
    setState(() => _state = _SaveState.saving);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await widget.notes.save(_draft());
      if (!mounted) return true;
      setState(() {
        _saved = saved;
        _fill(saved);
        _state = _SaveState.idle;
      });
      if (saved == null) _toast(messenger, 'Пустая заметка удалена');
      return true;
    } catch (_) {
      if (mounted) setState(() => _state = _SaveState.error);
      return false;
    }
  }

  static void _toast(ScaffoldMessengerState? m, String text) => m
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _askClose() async {
    if (_state == _SaveState.saving) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.tokens.surface2,
        title: Text('Сохранить изменения в заметке?', style: AppText.title),
        content: const Text('Если закрыть без сохранения, правки пропадут'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Продолжить редактирование'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Не сохранять'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'discard':
        navigator.pop();
        _toast(messenger, 'Изменения не сохранены');
      case 'save':
        if (await _save() && mounted) {
          navigator.pop();
          if (_saved != null) _toast(messenger, 'Заметка сохранена');
        }
    }
  }

  void _addMoment() {
    final m = RegExp(r'^(\d{1,2}):([0-5]\d)$')
        .firstMatch(_momentTime.text.trim());
    final text = _momentText.text.trim();
    setState(() {
      if (m == null || int.parse(m[1]!) >= _episodeMinutes) {
        _momentError = 'Время в формате мм:сс, меньше $_episodeMinutes:00';
      } else if (text.isEmpty) {
        _momentError = 'Напишите пару слов о моменте';
      } else {
        _momentError = null;
        _moments = [
          ..._moments,
          NoteMoment(
            episode: _momentEpisode,
            timecode: Duration(
              minutes: int.parse(m[1]!),
              seconds: int.parse(m[2]!),
            ),
            text: text,
          ),
        ]..sort(_byPosition);
        _momentText.clear();
        _momentTime.clear();
      }
    });
  }

  static int _byPosition(NoteMoment a, NoteMoment b) {
    final e = a.episode.compareTo(b.episode);
    return e != 0
        ? e
        : (a.timecode ?? Duration.zero).compareTo(b.timecode ?? Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phone = MediaQuery.sizeOf(context).width < AppLayout.medium;
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty && _state != _SaveState.saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askClose();
      },
      child: ColoredBox(
        color: t.surface1,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: phone ? 'Назад' : 'Закрыть',
                      onPressed: () => Navigator.maybePop(context),
                      icon: Icon(
                        phone
                            ? Symbols.arrow_back_rounded
                            : Symbols.close_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'МОЯ ЗАМЕТКА',
                            style: AppText.overline.copyWith(color: t.fg2),
                          ),
                          Text(
                            widget.details.anime.title.preferred,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              Expanded(
                child: _loaded
                    ? _body(context, phone)
                    : const Center(child: CircularProgressIndicator()),
              ),
              Divider(height: 1, color: t.border),
              _footer(context, dirty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.bodyStrong),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _body(BuildContext context, bool phone) {
    final t = context.tokens;
    final showReasons =
        widget.status == ListStatus.dropped ||
        _reasons.isNotEmpty ||
        _dropText.text.trim().isNotEmpty ||
        (_saved?.hasDropReason ?? false);
    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 20, 0, phone ? 16 : 20, 20),
      children: [
        if (showReasons)
          _section('Почему бросили', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in {...TitleNote.dropReasonHints, ..._reasons})
                  PillButton(
                    label: r,
                    selected: _reasons.contains(r),
                    onPressed: () => setState(() {
                      _reasons = _reasons.contains(r)
                          ? (_reasons.toList()..remove(r))
                          : [..._reasons, r];
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dropText,
              minLines: 2,
              maxLines: 5,
              inputFormatters: [
                LengthLimitingTextInputFormatter(TitleNote.maxDropText),
              ],
              decoration: const InputDecoration(
                labelText: 'Своими словами',
                hintText: 'Например: после 4-й серии потерял интерес',
              ),
            ),
          ]),
        _section('Что понравилось', [
          TextField(
            key: const ValueKey('note-liked'),
            controller: _liked,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Музыка, персонажи, отдельные серии…',
            ),
          ),
        ]),
        _section('Запомнившиеся моменты', [
          if (_moments.isEmpty)
            Text(
              'Пока нет. Добавьте серию, время и пару слов.',
              style: AppText.caption.copyWith(color: t.fg2),
            ),
          for (var i = 0; i < _moments.length; i++)
            _MomentRow(
              moment: _moments[i],
              onDelete: () =>
                  setState(() => _moments = _moments.toList()..removeAt(i)),
            ),
          const SizedBox(height: 8),
          _momentAdd(context),
          if (_momentError case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(e, style: AppText.label.copyWith(color: t.bad)),
            ),
        ]),
        _section('Вердикт', [_verdictGrid(context)]),
        _section('Итог одной-двумя строками', [
          TextField(
            key: const ValueKey('note-summary'),
            controller: _summary,
            minLines: 2,
            maxLines: 3,
            maxLength: TitleNote.maxSummary,
            decoration: const InputDecoration(
              hintText: 'Это увидите в «Моих списках» под названием',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _momentAdd(BuildContext context) {
    final episode = DropdownButtonFormField<int>(
      initialValue: _momentEpisode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Серия'),
      items: [
        for (var e = 1; e <= _episodeCount; e++)
          DropdownMenuItem(value: e, child: Text('$e')),
      ],
      onChanged: (e) => setState(() => _momentEpisode = e ?? _momentEpisode),
    );
    final time = TextField(
      controller: _momentTime,
      keyboardType: TextInputType.datetime,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: const InputDecoration(labelText: 'Время', hintText: 'мм:сс'),
      onSubmitted: (_) => _momentTextFocus.requestFocus(),
    );
    final text = TextField(
      controller: _momentText,
      focusNode: _momentTextFocus,
      inputFormatters: [LengthLimitingTextInputFormatter(80)],
      decoration: const InputDecoration(
        labelText: 'Что произошло',
        hintText: 'Коротко',
      ),
      onSubmitted: (_) => _addMoment(),
    );
    final add = OutlinedButton.icon(
      onPressed: _addMoment,
      icon: const Icon(Symbols.add_rounded, size: 18),
      label: const Text('Добавить'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 96, child: episode),
            const SizedBox(width: 8),
            SizedBox(width: 96, child: time),
            const SizedBox(width: 8),
            Expanded(child: text),
          ],
        ),
        const SizedBox(height: 8),
        add,
      ],
    );
  }

  Widget _verdictGrid(BuildContext context) {
    final t = context.tokens;
    const order = [
      NoteVerdict.rewatch,
      NoteVerdict.recommend,
      NoteVerdict.notRecommend,
      NoteVerdict.none,
    ];
    Widget cell(NoteVerdict v) {
      final vis = verdictVisual(v, t);
      final selected = v == _verdict;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? t.accentSoft : null,
            side: BorderSide(color: selected ? t.accent : t.border),
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () => setState(() => _verdict = v),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(vis.icon, size: 18, color: vis.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  vis.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: t.fg),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
            child: Row(
              children: [
                Expanded(child: cell(order[row * 2])),
                const SizedBox(width: 8),
                Expanded(child: cell(order[row * 2 + 1])),
              ],
            ),
          ),
      ],
    );
  }

  Widget _footer(BuildContext context, bool dirty) {
    final t = context.tokens;
    final error = _state == _SaveState.error;
    final Widget status;
    if (error) {
      status = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.cloud_off_rounded, size: 18, color: t.bad),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось сохранить: нет связи с хранилищем. '
              'Изменения не потеряны — они остаются в редакторе',
              style: AppText.label.copyWith(color: t.bad),
            ),
          ),
        ],
      );
    } else {
      final saved = _saved;
      final (String text, bool check) = switch (_state) {
        _SaveState.saving => ('Сохраняем…', false),
        _ when dirty => ('Есть несохранённые изменения', false),
        _ when saved != null => (
          'Сохранено · ${Fmt.relative(saved.updatedAt.toLocal())}',
          true,
        ),
        _ => ('Новая заметка', false),
      };
      status = Row(
        children: [
          if (check) ...[
            Icon(Symbols.check_rounded, size: 16, color: t.good),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(text, style: AppText.label.copyWith(color: t.fg2)),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(child: Semantics(liveRegion: true, child: status)),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _state == _SaveState.saving || (!dirty && !error)
                ? null
                : _save,
            child: Text(error ? 'Повторить' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.moment, required this.onDelete});

  final NoteMoment moment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final where = [
      'Серия ${moment.episode}',
      ?moment.timecodeLabel,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Text(where, style: AppText.labelStrong.copyWith(color: t.accent)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              moment.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
          ),
          IconButton(
            tooltip: 'Удалить момент «${moment.text}»',
            onPressed: onDelete,
            icon: const Icon(Symbols.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
