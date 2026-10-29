import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository lib;
  var now = DateTime.utc(2026, 1, 1);
  var changes = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 1, 1);
    changes = 0;
    lib = LibraryRepository(db, clock: () => now)..onChanged = () => changes++;
  });
  tearDown(() => db.close());

  test('first watched episode sets CURRENT, last sets COMPLETED', () async {
    final r1 = await lib.markWatched(1, 1, totalEpisodes: 3);
    expect(r1.before, isNull);
    expect(r1.after.status, ListStatus.current);
    expect(r1.after.progress, 1);

    final r2 = await lib.markWatched(1, 3, totalEpisodes: 3);
    expect(r2.after.status, ListStatus.completed);
    expect(r2.after.progress, 3);
    expect(changes, 2);
  });

  test(
    'planned title becomes CURRENT; rewatching an old episode is a no-op',
    () async {
      await lib.setStatus(1, ListStatus.planning);
      expect(
        (await lib.markWatched(1, 2, totalEpisodes: 12)).after.status,
        ListStatus.current,
      );
      final again = await lib.markWatched(1, 1, totalEpisodes: 12);
      expect(again.after.progress, 2);
      expect(again.after.status, ListStatus.current);
    },
  );

  test('unmark lowers progress and reopens a completed title', () async {
    await lib.markWatched(1, 12, totalEpisodes: 12);
    final r = await lib.unmarkWatched(1, 12);
    expect(r.after.progress, 11);
    expect(r.after.status, ListStatus.current);
  });

  test('restore undoes to the previous state or removes the title', () async {
    final r = await lib.markWatched(1, 1, totalEpisodes: 12);
    now = now.add(const Duration(seconds: 1));
    await lib.restore(1, r.before);
    expect(await lib.entry(1), isNull);

    await lib.setStatus(2, ListStatus.paused);
    final r2 = await lib.markWatched(2, 3);
    now = now.add(const Duration(seconds: 1));
    await lib.restore(2, r2.before);
    final e = await lib.entry(2);
    expect(e?.status, ListStatus.paused);
    expect(e?.progress, 0);
    expect(e?.updatedAt, now, reason: 'restore is a new change for sync');
  });

  test('watchEntry emits changes', () async {
    final events = <ListStatus?>[];
    final sub = lib.watchEntry(5).listen((e) => events.add(e?.status));
    await pumpEventQueue();
    await lib.setStatus(5, ListStatus.planning);
    await pumpEventQueue();
    await lib.remove(5);
    await pumpEventQueue();
    await sub.cancel();
    expect(events, [null, ListStatus.planning, null]);
  });
}
