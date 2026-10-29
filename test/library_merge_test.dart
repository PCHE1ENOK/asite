import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/sync/library_codec.dart';
import 'package:anime_viewer/data/sync/library_merge.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryEntry e(
  int id,
  ListStatus status,
  int minute, {
  int progress = 0,
  bool deleted = false,
}) => LibraryEntry(
  mediaId: id,
  status: status,
  progress: progress,
  updatedAt: DateTime.utc(2026, 1, 1, 0, minute),
  deleted: deleted,
);

void main() {
  group('merge', () {
    test('keeps the later updatedAt per title', () {
      final local = [
        e(1, ListStatus.current, 10, progress: 3),
        e(2, ListStatus.planning, 5),
      ];
      final remote = [
        e(1, ListStatus.current, 5, progress: 1),
        e(2, ListStatus.completed, 20),
        e(3, ListStatus.dropped, 1),
      ];

      final r = mergeLibraries(local, remote);

      expect(r.entries, [local[0], remote[1], remote[2]]);
      expect(r.localChanged, [remote[1], remote[2]]);
      expect(r.remoteChanged, isTrue);
      expect(r.conflicts, 2);
    });

    test('equal timestamps prefer local; identical lists change nothing', () {
      final a = e(1, ListStatus.current, 10);
      final b = e(1, ListStatus.paused, 10);
      expect(mergeLibraries([a], [b]).entries, [a]);

      final r = mergeLibraries([a], [a]);
      expect(r.localChanged, isEmpty);
      expect(r.remoteChanged, isFalse);
    });

    test('newer deletion wins over older entry and propagates', () {
      final r = mergeLibraries(
        [e(1, ListStatus.current, 1)],
        [e(1, ListStatus.current, 2, deleted: true)],
      );
      expect(r.entries.single.deleted, isTrue);
      expect(r.localChanged, hasLength(1));
      expect(r.remoteChanged, isFalse);
    });
  });

  group('codec', () {
    test('round-trips entries', () {
      final entries = [
        LibraryEntry(
          mediaId: 16498,
          status: ListStatus.completed,
          progress: 25,
          score: 9,
          updatedAt: DateTime.utc(2026, 3, 4, 5, 6, 7, 890),
        ),
        e(2, ListStatus.dropped, 1, deleted: true),
      ];
      expect(LibraryCodec.decode(LibraryCodec.encode(entries)), entries);
    });

    test('skips broken entries and tolerates garbage', () {
      expect(LibraryCodec.decode(null), isEmpty);
      expect(LibraryCodec.decode('not json'), isEmpty);
      expect(LibraryCodec.decode('[]'), isEmpty);
      final list = LibraryCodec.decode('''
        {"version": 1, "entries": [
          {"mediaId": 1, "status": "CURRENT", "updatedAt": "2026-01-01T00:00:00.000Z"},
          {"mediaId": 2, "status": "UNKNOWN", "updatedAt": "2026-01-01T00:00:00.000Z"},
          {"mediaId": "x"}
        ]}''');
      expect(list.single.mediaId, 1);
      expect(list.single.progress, 0);
    });
  });
}
