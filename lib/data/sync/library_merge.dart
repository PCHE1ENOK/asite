import '../models/library_entry.dart';

/// Результат слияния.
class MergeResult {
  const MergeResult({
    required this.entries,
    required this.localChanged,
    required this.remoteChanged,
    required this.conflicts,
  });

  /// Итоговые записи, по одной на тайтл, отсортированы по `mediaId`.
  final List<LibraryEntry> entries;

  /// Записи, которые нужно записать в локальную базу.
  final List<LibraryEntry> localChanged;

  /// Нужно ли перезаписать Gist.
  final bool remoteChanged;

  /// Сколько тайтлов есть с обеих сторон с разными записями
  /// (по ним взята более свежая).
  final int conflicts;
}

/// Сливает локальные и удалённые записи: по каждому тайтлу остаётся запись
/// с более поздним `updatedAt`, тайтлы только с одной стороны сохраняются.
///
/// При равном `updatedAt` побеждает локальная запись, чтобы не было
/// лишних перезаписей.
MergeResult mergeLibraries(
  Iterable<LibraryEntry> local,
  Iterable<LibraryEntry> remote,
) {
  final localById = {for (final e in local) e.mediaId: e};
  final remoteById = {for (final e in remote) e.mediaId: e};

  final merged = Map.of(localById);
  var conflicts = 0;
  for (final r in remoteById.values) {
    final l = merged[r.mediaId];
    if (l != null && l != r) conflicts++;
    if (l == null || r.updatedAt.isAfter(l.updatedAt)) merged[r.mediaId] = r;
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
    conflicts: conflicts,
  );
}
