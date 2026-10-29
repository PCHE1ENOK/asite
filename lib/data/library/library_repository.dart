import 'package:drift/drift.dart';

import '../cache/app_database.dart';
import '../models/library_entry.dart';

/// Списки пользователя на устройстве.
///
/// Каждое изменение получает `updatedAt` = текущее время и флаг `dirty`
/// до отправки в Gist; после изменения вызывается [onChanged].
class LibraryRepository {
  LibraryRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// Вызывается после каждого локального изменения (для автоотправки).
  void Function()? onChanged;

  Future<LibraryEntry?> entry(int mediaId) async {
    final row = await (_db.select(
      _db.libraryEntries,
    )..where((t) => t.mediaId.equals(mediaId))).getSingleOrNull();
    final e = row == null ? null : _fromRow(row);
    return e == null || e.deleted ? null : e;
  }

  /// Записи без удалённых, по убыванию времени изменения.
  Stream<List<LibraryEntry>> watchEntries({ListStatus? status}) {
    final q = _db.select(_db.libraryEntries)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    if (status != null) q.where((t) => t.status.equals(status.apiValue));
    return q.watch().map((rows) => [for (final r in rows) ?_fromRow(r)]);
  }

  Stream<LibraryEntry?> watchEntry(int mediaId) =>
      (_db.select(
        _db.libraryEntries,
      )..where((t) => t.mediaId.equals(mediaId))).watchSingleOrNull().map((r) {
        final e = r == null ? null : _fromRow(r);
        return e == null || e.deleted ? null : e;
      });

  /// Отмечает серию [episode] просмотренной: прогресс поднимается до неё.
  /// Тайтл без статуса становится «Смотрю», последняя серия —
  /// «Просмотрено». Возвращает прежнюю запись для «Отменить».
  Future<({LibraryEntry? before, LibraryEntry after})> markWatched(
    int mediaId,
    int episode, {
    int? totalEpisodes,
  }) async {
    final before = await entry(mediaId);
    final last = totalEpisodes != null && episode >= totalEpisodes;
    final after = await _update(mediaId, (e) {
      // Уже просмотренная серия ничего не меняет.
      if (!last && episode <= e.progress && before != null) return e;
      final progress = episode > e.progress ? episode : e.progress;
      final status = last
          ? ListStatus.completed
          : e.status == ListStatus.completed ||
                e.status == ListStatus.planning ||
                e.status == ListStatus.paused
          ? ListStatus.current
          : e.status;
      return e.copyWith(progress: progress, status: status);
    }, defaultStatus: ListStatus.current);
    return (before: before, after: after);
  }

  /// Снимает отметку: прогресс становится [episode] - 1.
  Future<({LibraryEntry? before, LibraryEntry after})> unmarkWatched(
    int mediaId,
    int episode,
  ) async {
    final before = await entry(mediaId);
    final after = await _update(
      mediaId,
      (e) => e.copyWith(
        progress: episode - 1,
        status: e.status == ListStatus.completed ? ListStatus.current : null,
      ),
      defaultStatus: ListStatus.current,
    );
    return (before: before, after: after);
  }

  /// Возвращает тайтл к прежнему состоянию («Отменить»): [previous] или,
  /// если записи не было, убирает его из списков.
  Future<void> restore(int mediaId, LibraryEntry? previous) async {
    if (previous == null) return remove(mediaId);
    await _write(previous.copyWith(updatedAt: _stamp()), dirty: true);
    onChanged?.call();
  }

  /// Все записи, включая удалённые, для синхронизации.
  Future<List<LibraryEntry>> allForSync() async => [
    for (final r in await _db.select(_db.libraryEntries).get()) ?_fromRow(r),
  ];

  /// Есть ли на устройстве хотя бы один тайтл в списках.
  Future<bool> hasEntries() async {
    final row =
        await (_db.select(_db.libraryEntries)
              ..where((t) => t.deleted.equals(false))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Stream<int> watchPendingCount() {
    final count = _db.libraryEntries.mediaId.count();
    final q = _db.selectOnly(_db.libraryEntries)
      ..addColumns([count])
      ..where(_db.libraryEntries.dirty.equals(true));
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  Future<int> pendingCount() => watchPendingCount().first;

  /// Ставит статус; при первом добавлении прогресс 0.
  Future<LibraryEntry> setStatus(int mediaId, ListStatus status) =>
      _update(mediaId, (e) => e.copyWith(status: status, deleted: false));

  Future<LibraryEntry> setProgress(
    int mediaId,
    int progress, {
    ListStatus defaultStatus = ListStatus.current,
  }) => _update(
    mediaId,
    (e) => e.copyWith(progress: progress < 0 ? 0 : progress),
    defaultStatus: defaultStatus,
  );

  Future<LibraryEntry> setScore(int mediaId, int? score) => _update(
    mediaId,
    (e) => e.copyWith(score: () => score),
    defaultStatus: ListStatus.completed,
  );

  /// Убирает тайтл из списков (запись остаётся как удалённая).
  Future<void> remove(int mediaId) async {
    final row = await (_db.select(
      _db.libraryEntries,
    )..where((t) => t.mediaId.equals(mediaId))).getSingleOrNull();
    final e = row == null ? null : _fromRow(row);
    if (e == null || e.deleted) return;
    await _write(e.copyWith(deleted: true, updatedAt: _stamp()), dirty: true);
    onChanged?.call();
  }

  /// Записывает результат слияния. Записи из Gist чистые, остальные
  /// остаются `dirty` до отправки. Запись пропускается, если тайтл успели
  /// изменить после чтения [snapshot]: новое изменение уйдёт следующей
  /// синхронизацией.
  Future<void> applyMerged(
    List<LibraryEntry> changed, {
    required Map<int, LibraryEntry> snapshot,
    required bool Function(LibraryEntry) isClean,
  }) => _db.transaction(() async {
    for (final e in changed) {
      final row = await (_db.select(
        _db.libraryEntries,
      )..where((t) => t.mediaId.equals(e.mediaId))).getSingleOrNull();
      final current = row == null ? null : _fromRow(row);
      if (current != snapshot[e.mediaId]) continue;
      await _write(e, dirty: !isClean(e));
    }
  });

  /// Снимает `dirty` с записей, отправленных в Gist, если их не успели
  /// изменить во время отправки.
  Future<void> markSynced(List<LibraryEntry> pushed) => _db.transaction(
    () async {
      for (final e in pushed) {
        await (_db.update(_db.libraryEntries)..where(
              (t) =>
                  t.mediaId.equals(e.mediaId) & t.updatedAt.equals(e.updatedAt),
            ))
            .write(const LibraryEntriesCompanion(dirty: Value(false)));
      }
    },
  );

  Future<LibraryEntry> _update(
    int mediaId,
    LibraryEntry Function(LibraryEntry) change, {
    ListStatus defaultStatus = ListStatus.planning,
  }) async {
    final row = await (_db.select(
      _db.libraryEntries,
    )..where((t) => t.mediaId.equals(mediaId))).getSingleOrNull();
    final now = _stamp();
    var current = row == null ? null : _fromRow(row);
    if (current == null || current.deleted) {
      current = LibraryEntry(
        mediaId: mediaId,
        status: defaultStatus,
        updatedAt: now,
      );
    }
    final next = change(current).copyWith(updatedAt: now);
    await _write(next, dirty: true);
    onChanged?.call();
    return next;
  }

  /// Время изменения в UTC с точностью до миллисекунд (как в JSON Gist).
  DateTime _stamp() => DateTime.fromMillisecondsSinceEpoch(
    _now().millisecondsSinceEpoch,
    isUtc: true,
  );

  Future<void> _write(LibraryEntry e, {required bool dirty}) => _db
      .into(_db.libraryEntries)
      .insertOnConflictUpdate(
        LibraryEntriesCompanion.insert(
          mediaId: Value(e.mediaId),
          status: e.status.apiValue,
          progress: Value(e.progress),
          score: Value(e.score),
          updatedAt: e.updatedAt,
          deleted: Value(e.deleted),
          dirty: Value(dirty),
        ),
      );

  static LibraryEntry? _fromRow(LibraryEntryRow r) {
    final status = ListStatus.fromApi(r.status);
    if (status == null) return null;
    return LibraryEntry(
      mediaId: r.mediaId,
      status: status,
      progress: r.progress,
      score: r.score,
      updatedAt: r.updatedAt.toUtc(),
      deleted: r.deleted,
    );
  }
}
