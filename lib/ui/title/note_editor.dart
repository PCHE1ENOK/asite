import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/anime.dart';
import '../../data/models/library_entry.dart';
import '../../data/models/title_note.dart';
import '../../data/notes/notes_repository.dart';
import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/filter_controls.dart';

const verdictLabels = {
  NoteVerdict.none: 'Без вердикта',
  NoteVerdict.rewatch: 'Стоит пересмотреть',
  NoteVerdict.recommend: 'Советую',
  NoteVerdict.notRecommend: 'Не советую',
};

/// Вкладка «Заметка»: личная заметка о тайтле в текущем профиле.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.details});

  final AnimeDetails details;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _summary = TextEditingController();
  final _liked = TextEditingController();
  final _reason = TextEditingController();
  NoteVerdict _verdict = NoteVerdict.none;
  List<NoteMoment> _moments = [];
  bool _loaded = false;
  bool _exists = false;

  /// Есть несохранённые изменения: сохраним при уходе с вкладки.
  bool _dirty = false;
  NotesRepository? _repo;

  void _markDirty() => _dirty = true;

  int get _id => widget.details.id;

  @override
  void initState() {
    super.initState();
    for (final c in [_summary, _liked, _reason]) {
      c.addListener(_markDirty);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = AppScope.of(context).services.notes;
    if (!_loaded) _load();
  }

  TitleNote _current() => TitleNote(
    mediaId: _id,
    updatedAt: DateTime.now(),
    summary: _summary.text,
    verdict: _verdict,
    liked: _liked.text,
    dropReason: _reason.text,
    moments: _moments,
  );

  Future<void> _load() async {
    _loaded = true;
    final n = await AppScope.of(context).services.notes.note(_id);
    if (!mounted) return;
    setState(() => _fill(n));
    _dirty = false;
  }

  void _fill(TitleNote? n) {
    _exists = n != null;
    _summary.text = n?.summary ?? '';
    _liked.text = n?.liked ?? '';
    _reason.text = n?.dropReason ?? '';
    _verdict = n?.verdict ?? NoteVerdict.none;
    _moments = [...?n?.moments];
  }

  @override
  void dispose() {
    final repo = _repo;
    if (_dirty && repo != null && (_exists || !_current().isEmpty)) {
      repo.save(_current());
    }
    _summary.dispose();
    _liked.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notes = AppScope.of(context).services.notes;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await notes.save(_current());
    if (!mounted) return;
    setState(() => _fill(saved));
    _dirty = false;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'Заметка пуста — удалена' : 'Заметка сохранена',
          ),
        ),
      );
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    await AppScope.of(context).services.notes.delete(_id);
    if (!mounted) return;
    setState(() => _fill(null));
    _dirty = false;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Заметка удалена')));
  }

  Future<void> _addMoment() async {
    final m = await showDialog<NoteMoment>(
      context: context,
      builder: (_) => _MomentDialog(maxEpisode: widget.details.anime.episodes),
    );
    if (m != null) {
      setState(() => _moments = [..._moments, m]);
      _dirty = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = AppScope.of(context).library[_id]?.status;
    final showReason =
        status == ListStatus.dropped || _reason.text.trim().isNotEmpty;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppText.overline.copyWith(color: t.fg2),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.lock_rounded, size: 16, color: t.fg3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Личная заметка — видна только в профиле «${AppScope.of(context).services.profile.name}»',
                  style: AppText.label.copyWith(color: t.fg2),
                ),
              ),
            ],
          ),
          label('Краткий итог'),
          TextField(
            controller: _summary,
            maxLines: 2,
            maxLength: TitleNote.maxSummary,
            decoration: const InputDecoration(
              hintText: 'Одна-две строки — видны в «Моих списках»',
            ),
          ),
          label('Вердикт'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in NoteVerdict.values)
                PillButton(
                  label: verdictLabels[v]!,
                  selected: v == _verdict,
                  onPressed: () => setState(() {
                    _verdict = v;
                    _dirty = true;
                  }),
                ),
            ],
          ),
          label('Что понравилось'),
          TextField(
            controller: _liked,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Персонажи, музыка, сцены…',
            ),
          ),
          if (showReason) ...[
            label('Почему брошено'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hint in TitleNote.dropReasonHints)
                  PillButton(
                    label: hint,
                    onPressed: () => setState(() {
                      final cur = _reason.text.trim();
                      _reason.text = cur.isEmpty
                          ? hint
                          : '$cur, ${hint.toLowerCase()}';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 5,
              maxLength: TitleNote.maxDropReason,
              decoration: const InputDecoration(hintText: 'Причина'),
            ),
          ],
          label('Запомнившиеся моменты'),
          for (var i = 0; i < _moments.length; i++)
            _MomentRow(
              moment: _moments[i],
              onDelete: () => setState(() {
                _moments = [..._moments]..removeAt(i);
                _dirty = true;
              }),
            ),
          TextButton.icon(
            onPressed: _addMoment,
            icon: const Icon(Symbols.add_rounded),
            label: const Text('Добавить момент'),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Symbols.save_rounded),
                label: const Text('Сохранить заметку'),
              ),
              if (_exists)
                OutlinedButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Symbols.delete_rounded),
                  label: const Text('Удалить заметку'),
                ),
            ],
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  where,
                  style: AppText.labelStrong.copyWith(color: t.accent),
                ),
                Text(moment.text, style: AppText.body),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Удалить момент',
            onPressed: onDelete,
            icon: const Icon(Symbols.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _MomentDialog extends StatefulWidget {
  const _MomentDialog({this.maxEpisode});

  final int? maxEpisode;

  @override
  State<_MomentDialog> createState() => _MomentDialogState();
}

class _MomentDialogState extends State<_MomentDialog> {
  final _episode = TextEditingController(text: '1');
  final _time = TextEditingController();
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _episode.dispose();
    _time.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final ep = int.tryParse(_episode.text.trim());
    final max = widget.maxEpisode;
    if (ep == null || ep < 1 || (max != null && ep > max)) {
      setState(
        () => _error = 'Номер серии от 1${max == null ? '' : ' до $max'}',
      );
      return;
    }
    final timecode = NoteMoment.parseTimecode(_time.text);
    if (_time.text.trim().isNotEmpty && timecode == null) {
      setState(() => _error = 'Таймкод в формате 12:34 или 1:02:03');
      return;
    }
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Опишите момент');
      return;
    }
    Navigator.pop(
      context,
      NoteMoment(episode: ep, timecode: timecode, text: _text.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.tokens.surface2,
    title: Text('Момент', style: AppText.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _episode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Серия'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _time,
                  decoration: const InputDecoration(
                    labelText: 'Таймкод (необязательно)',
                    hintText: '12:34',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Что запомнилось',
              errorText: _error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Добавить')),
    ],
  );
}
