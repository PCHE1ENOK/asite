import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/data/notes/notes_repository.dart';
import 'package:anime_viewer/data/profiles/profile_repository.dart';
import 'package:anime_viewer/data/sync/library_codec.dart';
import 'package:anime_viewer/data/sync/library_merge.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

TitleNote note(int id, {String summary = 'Итог', int minute = 0}) => TitleNote(
  mediaId: id,
  summary: summary,
  updatedAt: DateTime.utc(2026, 1, 1, 0, minute),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late NotesRepository notes;
  var now = DateTime.utc(2026, 5, 1);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 5, 1);
    notes = NotesRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('save and read a full note', () async {
    final saved = await notes.save(
      TitleNote(
        mediaId: 1,
        updatedAt: DateTime(2000),
        summary: '  Лучшее за сезон ',
        verdict: NoteVerdict.recommend,
        liked: 'Музыка',
        dropReason: 'x' * 600,
        moments: const [
          NoteMoment(episode: 5, text: 'Финал'),
          NoteMoment(
            episode: 2,
            timecode: Duration(minutes: 12, seconds: 3),
            text: 'Бой',
          ),
          NoteMoment(episode: 3, text: '   '),
        ],
      ),
    );
    expect(saved!.updatedAt, now, reason: 'stamped on save');

    final n = (await notes.note(1))!;
    expect(n.summary, 'Лучшее за сезон');
    expect(n.verdict, NoteVerdict.recommend);
    expect(n.liked, 'Музыка');
    expect(n.dropReason.length, TitleNote.maxDropReason);
    expect(n.moments.map((m) => m.episode), [
      2,
      5,
    ], reason: 'sorted, empty dropped');
    expect(n.moments.first.timecodeLabel, '12:03');
    expect(await notes.pendingCount(), 1);
  });

  test('empty note deletes; delete keeps a tombstone for sync', () async {
    await notes.save(note(1));
    now = now.add(const Duration(minutes: 1));
    expect(await notes.save(TitleNote(mediaId: 1, updatedAt: now)), isNull);
    expect(await notes.note(1), isNull);
    final all = await notes.allForSync();
    expect(all.single.deleted, isTrue);
  });

  test('notes are visible only in their profile', () async {
    final kaito = await ProfileRepository(db).create('Каито');
    final other = NotesRepository(db, profileId: kaito.id, clock: () => now);
    await notes.save(note(1, summary: 'мой'));
    await other.save(note(1, summary: 'чужой'));
    await other.save(note(2));

    expect((await notes.note(1))!.summary, 'мой');
    expect((await other.note(1))!.summary, 'чужой');
    expect(await notes.note(2), isNull);
    expect((await notes.allForSync()).map((n) => n.mediaId), [1]);

    // Удаление профиля удаляет его заметки.
    await ProfileRepository(db).delete(kaito.id);
    expect(await other.allForSync(), isEmpty);
    expect(await notes.note(1), isNotNull);
  });

  test('merge notes by updatedAt per note', () {
    final local = [note(1, summary: 'новое', minute: 10), note(2, minute: 5)];
    final remote = [
      note(1, summary: 'старое', minute: 1),
      note(2, summary: 'из Gist', minute: 20),
      note(3),
    ];
    final r = mergeNotes(local, remote);
    expect(r.entries.map((n) => n.summary), ['новое', 'из Gist', 'Итог']);
    expect(r.localChanged.map((n) => n.mediaId), [2, 3]);
    expect(r.remoteChanged, isTrue);
  });

  test('codec v2 round-trips notes; v1 files have no notes', () {
    final n = TitleNote(
      mediaId: 7,
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6, 7),
      summary: 's',
      verdict: NoteVerdict.rewatch,
      moments: const [
        NoteMoment(episode: 1, timecode: Duration(seconds: 75), text: 't'),
      ],
    );
    final file = LibraryCodec.decodeFile(
      LibraryCodec.encode(const [], notes: [n]),
    );
    expect(file.notes, [n]);
    expect(
      LibraryCodec.decodeFile('{"version":1,"entries":[]}').notes,
      isEmpty,
    );
  });

  test('timecode parsing', () {
    expect(
      NoteMoment.parseTimecode('12:34'),
      const Duration(minutes: 12, seconds: 34),
    );
    expect(
      NoteMoment.parseTimecode('1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(NoteMoment.parseTimecode('75'), const Duration(seconds: 75));
    expect(NoteMoment.parseTimecode('1:75'), isNull);
    expect(NoteMoment.parseTimecode('abc'), isNull);
    expect(NoteMoment.parseTimecode(''), isNull);
    expect(
      const NoteMoment(
        episode: 1,
        timecode: Duration(hours: 1, seconds: 5),
        text: '',
      ).timecodeLabel,
      '1:00:05',
    );
  });

  test('migration from v3 adds notes and keeps lists', () async {
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
            INSERT INTO profiles VALUES (1, 'Основной', 0, NULL, '2026-01-01T00:00:00.000Z');
            INSERT INTO library_entries VALUES (1, 16498, 'CURRENT', 3, NULL, '2026-01-01T00:00:00.000Z', 0, 0);
            PRAGMA user_version = 3;
          ''');
        },
      ),
    );
    notes = NotesRepository(db, clock: () => now);
    await notes.save(note(16498));
    expect((await notes.note(16498))!.summary, 'Итог');
    final rows = await db.select(db.libraryEntries).get();
    expect(rows.single.progress, 3);
  });
}
