import '../models/library_entry.dart';

/// Как совместить списки устройства и Gist.
enum MergeStrategy {
  /// По каждому тайтлу остаётся запись с более поздним `updatedAt`.
  merge,

  /// Списки берутся из Gist целиком.
  preferRemote,

  /// Списки берутся с устройства целиком.
  preferLocal,
}

/// Результат слияния.
class MergeResult {
  const MergeResult({
    required this.entries,
    required this.localChanged,
    required this.remoteChanged,
  });

  /// Итоговые записи, по одной на тайтл, отсортированы по `mediaId`.
  final List<LibraryEntry> entries;

  /// Записи, которые нужно записать в локальную базу.
  final List<LibraryEntry> localChanged;

  /// Нужно ли перезаписать Gist.
  final bool remoteChanged;
}

/// Сливает локальные и удалённые записи.
///
/// При равном `updatedAt` побеждает локальная запись, чтобы результат
/// не зависел от порядка устройств и не вызывал лишних записей.
MergeResult mergeLibraries(
  Iterable<LibraryEntry> local,
  Iterable<LibraryEntry> remote, {
  MergeStrategy strategy = MergeStrategy.merge,
  DateTime? now,
}) {
  final localById = {for (final e in local) e.mediaId: e};
  final remoteById = {for (final e in remote) e.mediaId: e};

  final Map<int, LibraryEntry> merged;
  switch (strategy) {
    case MergeStrategy.preferLocal:
      merged = Map.of(localById);
    case MergeStrategy.preferRemote:
      merged = Map.of(remoteById);
      // Тайтлы, которых нет в Gist, помечаются удалёнными с текущим
      // временем, чтобы удаление дошло и до других устройств.
      final deletedAt = (now ?? DateTime.now()).toUtc();
      for (final l in localById.values) {
        if (!merged.containsKey(l.mediaId) && !l.deleted) {
          merged[l.mediaId] = l.copyWith(deleted: true, updatedAt: deletedAt);
        }
      }
    case MergeStrategy.merge:
      merged = Map.of(localById);
      for (final r in remoteById.values) {
        final l = merged[r.mediaId];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          merged[r.mediaId] = r;
        }
      }
  }

  final ids = merged.keys.toList()..sort();
  final entries = [for (final id in ids) merged[id]!];
  return MergeResult(
    entries: entries,
    localChanged: [
      for (final e in entries)
        if (localById[e.mediaId] != e) e,
    ],
    remoteChanged:
        remoteById.length != entries.length ||
        entries.any((e) => remoteById[e.mediaId] != e),
  );
}
