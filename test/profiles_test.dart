import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    profiles = ProfileRepository(db);
  });
  tearDown(() => db.close());

  test('fresh database has the default profile', () async {
    final all = await profiles.all();
    expect(all.single.name, 'Основной');
    expect((await profiles.active()).id, AppDatabase.defaultProfileId);
  });

  test('name validation: empty, too long, duplicate', () async {
    await expectLater(
      profiles.create('  '),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'm',
          'Введите имя профиля',
        ),
      ),
    );
    await expectLater(
      profiles.create('x' * 21),
      throwsA(isA<ProfileException>()),
    );
    await expectLater(
      profiles.create('основной'),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'm',
          'Профиль с таким именем уже есть',
        ),
      ),
    );
    final p = await profiles.create(' Каито ', color: 7);
    expect(p.name, 'Каито');
    expect(p.color, 2);
  });

  test('two profiles do not see each other\'s lists', () async {
    final kaito = await profiles.create('Каито');
    final main = LibraryRepository(db);
    final other = LibraryRepository(db, profileId: kaito.id);

    await main.setStatus(1, ListStatus.current);
    await other.setStatus(1, ListStatus.dropped);
    await other.setStatus(2, ListStatus.planning);

    expect((await main.entry(1))!.status, ListStatus.current);
    expect((await other.entry(1))!.status, ListStatus.dropped);
    expect(await main.entry(2), isNull);
    expect((await main.allForSync()).map((e) => e.mediaId), [1]);
    expect(await main.pendingCount(), 1);
    expect(await other.pendingCount(), 2);
    expect(await profiles.entryCount(kaito.id), 2);

    await other.remove(1);
    expect((await main.entry(1))!.status, ListStatus.current);
  });

  test('recent searches are per profile', () async {
    final prefs = AppPreferences(db);
    await prefs.addRecentSearch(1, 'frieren');
    await prefs.addRecentSearch(2, 'naruto');
    expect(await prefs.recentSearches(1), ['frieren']);
    expect(await prefs.recentSearches(2), ['naruto']);
  });

  test('delete removes local data of that profile only', () async {
    final kaito = await profiles.create('Каито');
    final main = LibraryRepository(db);
    final other = LibraryRepository(db, profileId: kaito.id);
    await main.setStatus(1, ListStatus.current);
    await other.setStatus(2, ListStatus.planning);
    await AppPreferences(db).addRecentSearch(kaito.id, 'q');

    await profiles.delete(kaito.id);

    expect((await profiles.all()).map((p) => p.name), ['Основной']);
    expect(await other.allForSync(), isEmpty);
    expect(await AppPreferences(db).recentSearches(kaito.id), isEmpty);
    expect((await main.entry(1))!.status, ListStatus.current);
  });

  test('cannot delete the current or the last profile', () async {
    await expectLater(
      profiles.delete(AppDatabase.defaultProfileId),
      throwsA(isA<ProfileException>()),
    );
    final kaito = await profiles.create('Каито');
    await profiles.setActive(kaito.id);
    await expectLater(
      profiles.delete(kaito.id),
      throwsA(isA<ProfileException>()),
    );
    await profiles.delete(AppDatabase.defaultProfileId);
    await expectLater(
      profiles.delete(kaito.id),
      throwsA(isA<ProfileException>()),
    );
  });

  test('one GitHub account — one profile', () async {
    final kaito = await profiles.create('Каито');
    await profiles.bindGitHub(AppDatabase.defaultProfileId, 'Yuki-Dev');
    await expectLater(
      profiles.bindGitHub(kaito.id, 'yuki-dev'),
      throwsA(
        isA<GitHubAccountInUse>().having(
          (e) => e.profile.name,
          'profile',
          'Основной',
        ),
      ),
    );
    // Тот же профиль может привязаться заново.
    await profiles.bindGitHub(AppDatabase.defaultProfileId, 'Yuki-Dev');
    await profiles.unbindGitHub(AppDatabase.defaultProfileId);
    await profiles.bindGitHub(kaito.id, 'yuki-dev');
    expect((await profiles.byId(kaito.id))!.githubLogin, 'yuki-dev');
  });

  test('migration from v2 moves lists and settings to «Основной»', () async {
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
            CREATE TABLE library_entries (media_id INTEGER NOT NULL PRIMARY KEY,
              status TEXT NOT NULL, progress INTEGER NOT NULL DEFAULT 0,
              score INTEGER NULL, updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1);
            CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO library_entries VALUES
              (16498, 'CURRENT', 5, 9, '2026-01-01T00:00:00.000Z', 0, 0),
              (21, 'PLANNING', 0, NULL, '2026-01-02T00:00:00.000Z', 1, 1);
            INSERT INTO settings VALUES
              ('sync_login', 'octocat'), ('sync_gist_id', 'g1'),
              ('recent_searches', '["frieren"]'), ('show_adult', '0');
            PRAGMA user_version = 2;
          ''');
        },
      ),
    );
    profiles = ProfileRepository(db);

    final main = (await profiles.all()).single;
    expect(main.id, AppDatabase.defaultProfileId);
    expect(main.name, 'Основной');
    expect(main.githubLogin, 'octocat');
    expect((await profiles.active()).id, main.id);

    final lib = LibraryRepository(db);
    final entries = await lib.allForSync();
    expect(entries.map((e) => e.mediaId), unorderedEquals([16498, 21]));
    final aot = entries.firstWhere((e) => e.mediaId == 16498);
    expect(aot.progress, 5);
    expect(aot.score, 9);
    expect(aot.updatedAt, DateTime.utc(2026));
    expect(entries.firstWhere((e) => e.mediaId == 21).deleted, isTrue);
    expect(await lib.pendingCount(), 1);

    final prefs = AppPreferences(db);
    expect(await prefs.recentSearches(main.id), ['frieren']);
    expect(await prefs.showAdult(), isFalse, reason: 'device setting stays');
    expect(await db.setting('p1:sync_gist_id'), 'g1');
    expect(await db.setting('sync_gist_id'), isNull);
  });
}
