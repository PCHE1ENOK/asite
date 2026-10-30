import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/github_auth.dart';
import 'package:anime_viewer/data/github/github_exception.dart';
import 'package:anime_viewer/data/github/token_store.dart';
import 'package:anime_viewer/data/library/library_repository.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/data/notes/notes_repository.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/sync/library_codec.dart';
import 'package:anime_viewer/data/sync/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'github_fakes.dart';

void main() {
  late AppDatabase db;
  late FakeGitHub github;
  late DateTime now;
  late LibraryRepository library;
  late MemoryTokenStore tokens;
  late SyncService sync;

  SyncService makeSync() => SyncService(
    library: library,
    db: db,
    tokens: tokens,
    profiles: ProfileRepository(db),
    auth: () => GitHubAuth(
      clientId: 'client',
      httpClient: github.client,
      delay: (_) async {},
      clock: () => now,
    ),
    gistClient: (token) => GistClient(token, httpClient: github.client),
    debounce: const Duration(milliseconds: 200),
    clock: () => now,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    github = FakeGitHub();
    now = DateTime.utc(2026, 5, 1, 12);
    library = LibraryRepository(db, clock: () => now);
    tokens = MemoryTokenStore();
    sync = makeSync();
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  List<LibraryEntry> gistEntries() =>
      LibraryCodec.decode(github.gists.values.single[LibraryCodec.fileName]);

  Future<SignInResult> signIn() async =>
      sync.completeSignIn(await sync.requestDeviceCode());

  test('signed out: works locally and counts pending changes', () async {
    await sync.start();
    expect(sync.state.value.status, SyncStatus.signedOut);

    await library.setStatus(1, ListStatus.current);
    expect(await library.pendingCount(), 1);
    expect(github.writes, 0);
  });

  test('first sign-in creates a private Gist with device lists', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await library.setProgress(1, 4);
    await library.setStatus(2, ListStatus.planning);

    final result = await signIn();

    expect(result.login, 'octocat');
    expect(result.gistCreated, isTrue);
    expect(result.entryCount, 2);
    expect(tokens.token, 'tok');
    expect(gistEntries().map((e) => (e.mediaId, e.progress)), [(1, 4), (2, 0)]);
    expect(sync.state.value.status, SyncStatus.synced);
    expect(sync.state.value.login, 'octocat');
    expect(await library.pendingCount(), 0);
  });

  test('sign-in with lists on both sides merges by updatedAt', () async {
    github.gists['old'] = {
      LibraryCodec.fileName: LibraryCodec.encode([
        LibraryEntry(
          mediaId: 1,
          status: ListStatus.completed,
          progress: 12,
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
        LibraryEntry(
          mediaId: 3,
          status: ListStatus.paused,
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      ]),
    };
    await sync.start();
    await library.setStatus(1, ListStatus.current); // новее, чем в Gist
    await library.setStatus(3, ListStatus.dropped); // старше, чем в Gist

    await library.setStatus(4, ListStatus.planning); // только на устройстве

    final result = await signIn();

    expect(result.gistCreated, isFalse);
    expect(result.entryCount, 3);
    expect(result.conflicts, 2);
    expect((await library.entry(1))!.status, ListStatus.current);
    expect((await library.entry(3))!.status, ListStatus.paused);
    expect(gistEntries().map((e) => e.status), [
      ListStatus.current,
      ListStatus.paused,
      ListStatus.planning,
    ]);
    expect(await library.pendingCount(), 0);
  });

  test('local change is pushed automatically after debounce', () async {
    await sync.start();
    await signIn();
    final writesBefore = github.writes;

    now = now.add(const Duration(minutes: 1));
    await library.setProgress(5, 2);
    await pumpEventQueue();
    expect(sync.state.value.status, SyncStatus.pending);
    expect(sync.state.value.pendingCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(github.writes, greaterThan(writesBefore));
    await sync.syncNow(); // дождаться завершения, если отправка ещё идёт

    expect(github.writes, greaterThan(writesBefore));
    expect(gistEntries().single.mediaId, 5);
    expect(sync.state.value.status, SyncStatus.synced);
  });

  test('changes from another device arrive on app start', () async {
    await sync.start();
    await signIn();
    await sync.dispose();

    final gistId = github.gists.keys.single;
    github.gists[gistId]![LibraryCodec.fileName] = LibraryCodec.encode([
      LibraryEntry(
        mediaId: 42,
        status: ListStatus.current,
        progress: 3,
        updatedAt: DateTime.utc(2026, 5, 2),
      ),
    ]);

    sync = makeSync();
    await sync.start();
    expect((await library.entry(42))!.progress, 3);
  });

  test('removal propagates to Gist as deletion', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await signIn();

    now = now.add(const Duration(minutes: 1));
    await library.remove(1);
    await sync.syncNow();

    expect(gistEntries().single.deleted, isTrue);
    expect(await library.entry(1), isNull);
  });

  test('offline: error state, changes kept, retry succeeds', () async {
    await sync.start();
    await signIn();

    github.offline = true;
    now = now.add(const Duration(minutes: 1));
    await library.setStatus(9, ListStatus.planning);
    await sync.syncNow();
    expect(sync.state.value.status, SyncStatus.error);
    expect(sync.state.value.pendingCount, 1);

    github.offline = false;
    await sync.syncNow();
    expect(sync.state.value.status, SyncStatus.synced);
    expect(gistEntries().single.mediaId, 9);
  });

  test('revoked token signs out but keeps local lists', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await signIn();

    github.revoked = true;
    await sync.syncNow();

    expect(sync.state.value.status, SyncStatus.signedOut);
    expect(tokens.token, isNull);
    expect(await library.entry(1), isNotNull);
  });

  test('deleted Gist is recreated', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await signIn();
    github.gists.clear();

    await sync.syncNow();

    expect(gistEntries().single.mediaId, 1);
  });

  test('sign out keeps lists and Gist', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await signIn();

    await sync.signOut();

    expect(sync.state.value.status, SyncStatus.signedOut);
    expect(await library.entry(1), isNotNull);
    expect(github.gists, hasLength(1));
  });

  test('one GitHub account cannot be bound to two profiles', () async {
    await sync.start();
    await library.setStatus(1, ListStatus.current);
    await signIn();
    await sync.dispose();

    // Второй профиль входит тем же аккаунтом.
    final kaito = await ProfileRepository(db).create('Каито');
    final otherLib = LibraryRepository(
      db,
      profileId: kaito.id,
      clock: () => now,
    );
    await otherLib.setStatus(2, ListStatus.planning);
    final otherTokens = MemoryTokenStore();
    sync = SyncService(
      library: otherLib,
      db: db,
      tokens: otherTokens,
      profiles: ProfileRepository(db),
      auth: () => GitHubAuth(
        clientId: 'client',
        httpClient: github.client,
        delay: (_) async {},
        clock: () => now,
      ),
      gistClient: (token) => GistClient(token, httpClient: github.client),
      clock: () => now,
    );
    await sync.start();

    await expectLater(
      signIn(),
      throwsA(
        isA<GitHubException>()
            .having((e) => e.kind, 'kind', GitHubErrorKind.accountInUse)
            .having((e) => e.message, 'message', contains('«Основной»')),
      ),
    );
    expect(otherTokens.token, isNull);
    expect(sync.state.value.status, SyncStatus.signedOut);
    // Gist первого профиля не смешан со списками второго.
    expect(gistEntries().map((e) => e.mediaId), [1]);
    expect((await otherLib.entry(2))!.status, ListStatus.planning);
    expect(await library.entry(2), isNull);
  });

  test('sign-in binds the login to the profile; sign-out unbinds', () async {
    await sync.start();
    await signIn();
    final profiles = ProfileRepository(db);
    expect((await profiles.byId(1))!.githubLogin, 'octocat');
    await sync.signOut();
    expect((await profiles.byId(1))!.githubLogin, isNull);
  });

  test('notes sync with the lists in the same Gist file', () async {
    final notes = NotesRepository(db, clock: () => now);
    await sync.dispose();
    sync = SyncService(
      library: library,
      notes: notes,
      db: db,
      tokens: tokens,
      profiles: ProfileRepository(db),
      auth: () => GitHubAuth(
        clientId: 'client',
        httpClient: github.client,
        delay: (_) async {},
        clock: () => now,
      ),
      gistClient: (token) => GistClient(token, httpClient: github.client),
      clock: () => now,
    );
    await sync.start();
    await notes.save(
      TitleNote(mediaId: 1, updatedAt: now, summary: 'с устройства'),
    );
    await notes.save(TitleNote(mediaId: 2, updatedAt: now, summary: 'старая'));
    expect(sync.state.value.pendingCount, 0, reason: 'signed out');
    await signIn();

    var file = LibraryCodec.decodeFile(
      github.gists.values.single[LibraryCodec.fileName],
    );
    expect(file.notes.map((n) => n.summary), ['с устройства', 'старая']);
    expect(await notes.pendingCount(), 0);

    // Другое устройство обновило заметку 2 и добавило 3.
    final gistId = github.gists.keys.single;
    github.gists[gistId]![LibraryCodec.fileName] = LibraryCodec.encode(
      const [],
      notes: [
        file.notes.first,
        TitleNote(
          mediaId: 2,
          updatedAt: now.add(const Duration(hours: 1)),
          summary: 'новее',
        ),
        TitleNote(mediaId: 3, updatedAt: now, summary: 'с телефона'),
      ],
    );
    now = now.add(const Duration(minutes: 1));
    await notes.save(TitleNote(mediaId: 1, updatedAt: now, summary: 'правка'));
    await sync.syncNow();

    expect((await notes.note(1))!.summary, 'правка');
    expect((await notes.note(2))!.summary, 'новее');
    expect((await notes.note(3))!.summary, 'с телефона');
    file = LibraryCodec.decodeFile(
      github.gists.values.single[LibraryCodec.fileName],
    );
    expect(file.notes.map((n) => n.summary), ['правка', 'новее', 'с телефона']);
  });
}
