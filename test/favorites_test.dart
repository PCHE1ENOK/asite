import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/favorites/favorites_repository.dart';
import 'package:anime_viewer/data/models/favorite.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/sync/library_codec.dart';
import 'package:anime_viewer/data/sync/library_merge.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FavoritesRepository fav;
  var now = DateTime.utc(2026, 10, 31);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 31);
    fav = FavoritesRepository(db, clock: () => now);
  });
  tearDown(() async {
    await fav.dispose();
    await db.close();
  });

  test('toggle, tombstone for sync, pending count', () async {
    expect(await fav.toggle(1), isTrue);
    expect(fav.isFavorite(1), isTrue);
    expect(await fav.pendingCount(), 1);
    now = now.add(const Duration(minutes: 1));
    expect(await fav.toggle(1), isFalse);
    expect(fav.isFavorite(1), isFalse);
    final all = await fav.allForSync();
    expect(all.single.deleted, isTrue, reason: 'removal reaches other devices');
    // Повторное снятие ничего не пишет.
    await fav.set(2, false);
    expect(await fav.allForSync(), hasLength(1));
  });

  test('ids follow the database (incl. merged changes)', () async {
    expect(fav.ids.value, isEmpty);
    await fav.applyMerged(
      [Favorite(mediaId: 7, updatedAt: now)],
      snapshot: const {},
      isClean: (_) => true,
    );
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    expect(fav.ids.value, {7});
    expect(await fav.pendingCount(), 0, reason: 'clean from remote');
  });

  test('favorites are per profile', () async {
    final kaito = await ProfileRepository(db).create('Каито');
    final other = FavoritesRepository(
      db,
      profileId: kaito.id,
      clock: () => now,
    );
    await fav.set(1, true);
    expect((await other.allForSync()), isEmpty);
    await other.dispose();
  });

  test('migration from v4 adds favorites and keeps lists', () async {
    await fav.dispose();
    await db.close();
    db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE cached_anime (id INTEGER NOT NULL PRIMARY KEY,
              summary_json TEXT NOT NULL, summary_updated_at TEXT NOT NULL,
              details_json TEXT NULL, details_updated_at TEXT NULL);
            CREATE TABLE cache_entries (key TEXT NOT NULL PRIMARY KEY,
              payload TEXT NOT NULL, updated_at TEXT NOT NULL);
            CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE, color INTEGER NOT NULL DEFAULT 0,
              github_login TEXT NULL UNIQUE, created_at TEXT NOT NULL);
            CREATE TABLE library_entries (profile_id INTEGER NOT NULL REFERENCES profiles (id),
              media_id INTEGER NOT NULL, status TEXT NOT NULL,
              progress INTEGER NOT NULL DEFAULT 0, score INTEGER NULL,
              updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (profile_id, media_id));
            CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE notes (profile_id INTEGER NOT NULL REFERENCES profiles (id),
              media_id INTEGER NOT NULL, payload TEXT NOT NULL,
              updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (profile_id, media_id));
            INSERT INTO profiles VALUES (1, 'Основной', 0, NULL, '2026-01-01T00:00:00.000Z');
            INSERT INTO library_entries VALUES (1, 16498, 'CURRENT', 3, NULL, '2026-01-01T00:00:00.000Z', 0, 0);
            PRAGMA user_version = 4;
          ''');
        },
      ),
    );
    fav = FavoritesRepository(db, clock: () => now);
    await fav.set(16498, true);
    expect((await fav.allForSync()).single.mediaId, 16498);
    expect((await db.select(db.libraryEntries).get()).single.progress, 3);
  });

  test('codec v3 keeps favorites; older files read without them', () {
    final f = Favorite(mediaId: 3, updatedAt: now);
    final file = LibraryCodec.decodeFile(
      LibraryCodec.encode(const [], favorites: [f]),
    );
    expect(file.favorites, [f]);
    expect(
      LibraryCodec.decodeFile('{"version":2,"entries":[],"notes":[]}')
          .favorites,
      isEmpty,
    );
    expect(
      LibraryCodec.decodeFile(
        '{"version":3,"favorites":[{"mediaId":"x"},{"mediaId":4,"updatedAt":"2026-01-01T00:00:00Z","deleted":true}]}',
      ).favorites.single.deleted,
      isTrue,
    );
  });

  test('merge: newer mark wins, independent of the list status', () {
    final local = [
      Favorite(mediaId: 1, updatedAt: now),
      Favorite(mediaId: 2, updatedAt: now, deleted: true),
    ];
    final remote = [
      Favorite(
        mediaId: 1,
        updatedAt: now.add(const Duration(hours: 1)),
        deleted: true,
      ),
      Favorite(mediaId: 2, updatedAt: now.subtract(const Duration(hours: 1))),
      Favorite(mediaId: 3, updatedAt: now),
    ];
    final m = mergeFavorites(local, remote);
    expect(
      {for (final f in m.entries) f.mediaId: f.deleted},
      {1: true, 2: true, 3: false},
    );
    // Статус в списках — отдельная запись.
    expect(
      mergeLibraries([
        LibraryEntry(mediaId: 1, status: ListStatus.current, updatedAt: now),
      ], const []).entries.single.status,
      ListStatus.current,
    );
  });
}
