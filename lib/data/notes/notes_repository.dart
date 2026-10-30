import 'dart:convert';

import 'package:drift/drift.dart';

import '../cache/app_database.dart';
import '../models/title_note.dart';

/// Заметки о тайтлах одного профиля.
///
/// Как и списки: каждое сохранение получает `updatedAt` и флаг `dirty`
/// до отправки в Gist, удаление хранится отметкой.
class NotesRepository {
  NotesRepository(
    this._db, {
    this.profileId = AppDatabase.defaultProfileId,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final int profileId;
  final DateTime Function() _now;

  /// Вызывается после каждого изменения (для автоотправки).
  void Function()? onChanged;

  SimpleSelectStatement<$NotesTable, NoteRow> _one(int mediaId) => _db.select(
    _db.notes,
  )..where((t) => t.profileId.equals(profileId) & t.mediaId.equals(mediaId));

  Future<TitleNote?> note(int mediaId) async {
    final row = await _one(mediaId).getSingleOrNull();
    final n = row == null ? null : _fromRow(row);
    return n == null || n.deleted ? null : n;
  }

  Stream<TitleNote?> watchNote(int mediaId) =>
      _one(mediaId).watchSingleOrNull().map((r) {
        final n = r == null ? null : _fromRow(r);
        return n == null || n.deleted ? null : n;
      });

  /// Все заметки профиля без удалённых (для «Моих списков»).
  Stream<Map<int, TitleNote>> watchAll() =>
      (_db.select(_db.notes)..where(
            (t) => t.profileId.equals(profileId) & t.deleted.equals(false),
          ))
          .watch()
          .map(
            (rows) => {
              for (final n in rows.map(_fromRow).nonNulls) n.mediaId: n,
            },
          );

  /// Сохраняет заметку. Пустая заметка удаляет существующую.
  /// Причина «брошено» обрезается до [TitleNote.maxDropReason] символов.
  Future<TitleNote?> save(TitleNote note) async {
    if (note.isEmpty) {
      await delete(note.mediaId);
      return null;
    }
    final clean = note.copyWith(
      summary: _trim(note.summary, TitleNote.maxSummary),
      dropReason: _trim(note.dropReason, TitleNote.maxDropReason),
      liked: note.liked.trim(),
      moments:
          [
            for (final m in note.moments)
              if (m.text.trim().isNotEmpty && m.episode > 0)
                NoteMoment(
                  episode: m.episode,
                  timecode: m.timecode,
                  text: m.text.trim(),
                ),
          ]..sort((a, b) {
            final e = a.episode.compareTo(b.episode);
            return e != 0
                ? e
                : (a.timecode ?? Duration.zero).compareTo(
                    b.timecode ?? Duration.zero,
                  );
          }),
      updatedAt: _stamp(),
      deleted: false,
    );
    await _write(clean, dirty: true);
    onChanged?.call();
    return clean;
  }

  Future<void> delete(int mediaId) async {
    final row = await _one(mediaId).getSingleOrNull();
    final n = row == null ? null : _fromRow(row);
    if (n == null || n.deleted) return;
    await _write(n.copyWith(deleted: true, updatedAt: _stamp()), dirty: true);
    onChanged?.call();
  }

  Future<List<TitleNote>> allForSync() async => [
    for (final r in await (_db.select(
      _db.notes,
    )..where((t) => t.profileId.equals(profileId))).get())
      ?_fromRow(r),
  ];

  Stream<int> watchPendingCount() {
    final count = _db.notes.mediaId.count();
    final q = _db.selectOnly(_db.notes)
      ..addColumns([count])
      ..where(
        _db.notes.profileId.equals(profileId) & _db.notes.dirty.equals(true),
      );
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  Future<int> pendingCount() => watchPendingCount().first;

  /// Записывает результат слияния; заметку, изменённую после чтения
  /// [snapshot], не трогает.
  Future<void> applyMerged(
    List<TitleNote> changed, {
    required Map<int, TitleNote> snapshot,
    required bool Function(TitleNote) isClean,
  }) => _db.transaction(() async {
    for (final n in changed) {
      final row = await _one(n.mediaId).getSingleOrNull();
      final current = row == null ? null : _fromRow(row);
      if (current != snapshot[n.mediaId]) continue;
      await _write(n, dirty: !isClean(n));
    }
  });

  Future<void> markSynced(List<TitleNote> pushed) => _db.transaction(() async {
    for (final n in pushed) {
      await (_db.update(_db.notes)..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.mediaId.equals(n.mediaId) &
                t.updatedAt.equals(n.updatedAt),
          ))
          .write(const NotesCompanion(dirty: Value(false)));
    }
  });

  DateTime _stamp() => DateTime.fromMillisecondsSinceEpoch(
    _now().millisecondsSinceEpoch,
    isUtc: true,
  );

  static String _trim(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  Future<void> _write(TitleNote n, {required bool dirty}) => _db
      .into(_db.notes)
      .insertOnConflictUpdate(
        NotesCompanion.insert(
          profileId: profileId,
          mediaId: n.mediaId,
          payload: jsonEncode(n.toJson()),
          updatedAt: n.updatedAt,
          deleted: Value(n.deleted),
          dirty: Value(dirty),
        ),
      );

  static TitleNote? _fromRow(NoteRow r) {
    final json = jsonDecode(r.payload) as Map<String, dynamic>;
    return TitleNote.tryFromJson({
      ...json,
      'mediaId': r.mediaId,
      'updatedAt': r.updatedAt.toUtc().toIso8601String(),
      'deleted': r.deleted,
    });
  }
}
