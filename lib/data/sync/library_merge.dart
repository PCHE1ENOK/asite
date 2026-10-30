import '../models/library_entry.dart';
import '../models/title_note.dart';

/// Результат слияния.
class MergeResult<T> {
  const MergeResult({
    required this.entries,
    required this.localChanged,
    required this.remoteChanged,
    required this.conflicts,
  });

  /// Итоговые записи, по одной на тайтл, отсортированы по `mediaId`.
  final List<T> entries;

  /// Записи, которые нужно записать в локальную базу.
  final List<T> localChanged;

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
MergeResult<LibraryEntry> mergeLibraries(
  Iterable<LibraryEntry> local,
  Iterable<LibraryEntry> remote,
) => mergeRecords(
  local,
  remote,
  key: (e) => e.mediaId,
  updatedAt: (e) => e.updatedAt,
);

/// То же для заметок о тайтлах: по заметке побеждает более свежая.
MergeResult<TitleNote> mergeNotes(
  Iterable<TitleNote> local,
  Iterable<TitleNote> remote,
) => mergeRecords(
  local,
  remote,
  key: (n) => n.mediaId,
  updatedAt: (n) => n.updatedAt,
);

/// Слияние «последняя запись побеждает» по ключу [key].
MergeResult<T> mergeRecords<T>(
  Iterable<T> local,
  Iterable<T> remote, {
  required int Function(T) key,
  required DateTime Function(T) updatedAt,
}) {
  final localById = {for (final e in local) key(e): e};
  final remoteById = {for (final e in remote) key(e): e};

  final merged = Map.of(localById);
  var conflicts = 0;
  for (final r in remoteById.values) {
    final l = merged[key(r)];
    if (l != null && l != r) conflicts++;
    if (l == null || updatedAt(r).isAfter(updatedAt(l))) merged[key(r)] = r;
  }

  final ids = merged.keys.toList()..sort();
  final entries = [for (final id in ids) merged[id] as T];
  return MergeResult(
    entries: entries,
    localChanged: [
      for (final e in entries)
        if (localById[key(e)] != e) e,
    ],
    remoteChanged:
        remoteById.length != entries.length ||
        entries.any((e) => remoteById[key(e)] != e),
    conflicts: conflicts,
  );
}
