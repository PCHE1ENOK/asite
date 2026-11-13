import 'dart:convert';

import 'package:anime_viewer/data/cache/app_database.dart';
import 'package:anime_viewer/data/friends/friends_repository.dart';
import 'package:anime_viewer/data/github/gist_client.dart';
import 'package:anime_viewer/data/github/github_exception.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/share/share_codec.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'github_fakes.dart';

/// Каталог друга в формате share.json v1.
String catalogJson({String owner = 'Юки', int count = 3}) => jsonEncode({
  'version': 1,
  'owner': owner,
  'updatedAt': '2026-11-10T10:00:00Z',
  'titles': [
    {
      'id': 1,
      'title': {'ru': 'Фрирен', 'en': 'Frieren'},
      'status': 'CURRENT',
      'progress': 5,
      'episodes': 28,
      'favorite': true,
      'score': {'value': 9.1, 'source': 'shikimori'},
      'note': {
        'verdict': 'recommend',
        'summary': 'Тёплая и грустная',
        'moments': [
          {'episode': 3, 'time': '12:30', 'text': 'Цветы'},
        ],
      },
    },
    if (count > 1)
      {
        'id': 2,
        'title': {'romaji': 'Shingeki no Kyojin'},
        'status': 'COMPLETED',
        'adult': false,
      },
    if (count > 2)
      {
        'id': 3,
        'title': {'en': 'Dropped one'},
        'status': 'DROPPED',
      },
    {'broken': true},
  ],
});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeGitHub github;
  late DateTime now;
  String? token;

  FriendsRepository repo({int profileId = 1}) => FriendsRepository(
    db,
    profileId: profileId,
    token: () => token,
    gistClient: (t) => GistClient(t, httpClient: github.client),
    clock: () => now,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    github = FakeGitHub()
      ..users['yuki'] = 'https://avatars.githubusercontent.com/u/7?v=4'
      ..users['nocatalog'] = null
      ..userGists['yuki'] = {ShareCodec.fileName: catalogJson()};
    token = 'tok';
    now = DateTime.utc(2026, 11, 13, 10);
  });
  tearDown(() => db.close());

  group('search by GitHub nick', () {
    test('public catalog found: login, avatar, title count', () async {
      final r = await repo().find(' @Yuki ');
      expect(r, isA<FriendFound>());
      r as FriendFound;
      expect(r.login, 'yuki');
      expect(r.avatarUrl, 'https://avatars.githubusercontent.com/u/7?v=4');
      expect(r.titleCount, 3, reason: 'битая запись пропущена');
      expect(r.catalog!.owner, 'Юки');
      expect(r.catalog!.watching, 1);
      expect(r.catalog!.completed, 1);
      expect(r.catalog!.favorites, 1);
    });

    test('no public catalog / no such user / bad nick', () async {
      final r = repo();
      final none = await r.find('nocatalog');
      expect(none, isA<FriendNoCatalog>());
      expect((none as FriendNoCatalog).login, 'nocatalog');
      expect(await r.find('ghost'), isA<FriendNotFound>());
      expect(await r.find('no spaces!'), isA<FriendNotFound>());
    });

    test('secret Gist with the file is not found by nick', () async {
      // Публичных Gist нет: секретная публикация по нику не видна.
      github.userGists['nocatalog'] = {};
      expect(await repo().find('nocatalog'), isA<FriendNoCatalog>());
    });

    test('not signed in: search unavailable, no requests', () async {
      token = null;
      expect(await repo().find('yuki'), isA<FriendSignInRequired>());
      expect(github.apiRequests, 0);
    });

    test('rate limit: clear result, no crash', () async {
      github.rateLimited = true;
      final r = await repo().find('yuki');
      expect(r, isA<FriendRateLimited>());
      expect(
        (r as FriendRateLimited).retryAt,
        DateTime.utc(2026, 11, 13, 10, 30),
        reason: 'из X-RateLimit-Reset',
      );
    });
  });

  group('friends list', () {
    test('kept in the profile; other profile has its own', () async {
      final a = repo();
      await a.load();
      await a.add(await a.find('yuki') as FriendFound);
      expect(a.friends.value.single.login, 'yuki');
      expect(a.friends.value.single.addedAt, now);
      expect(a.friends.value.single.name, 'Юки');
      expect((await a.cached('yuki'))!.titles, hasLength(3));

      // После перезапуска — тот же список.
      final again = repo();
      expect((await again.load()).single.login, 'yuki');
      expect(
        (await again.load()).single.avatarUrl,
        'https://avatars.githubusercontent.com/u/7?v=4',
      );
      // Другой профиль — пусто.
      expect(await repo(profileId: 2).load(), isEmpty);

      await again.remove('YUKI');
      expect(again.friends.value, isEmpty);
      expect(await repo().load(), isEmpty);
    });

    test('add twice keeps one; restore after remove', () async {
      final r = repo();
      final found = await r.find('yuki') as FriendFound;
      await r.add(found);
      await r.add(found);
      expect(r.friends.value, hasLength(1));
      final friend = r.friends.value.single;
      await r.remove('yuki');
      await r.restore(friend);
      expect(r.friends.value, [friend]);
    });
  });

  group('friend catalog', () {
    test('parsed from the share file; notes as in the file', () async {
      final c = await repo().catalog('yuki');
      expect(c.owner, 'Юки');
      expect(c.titles.map((t) => t.title), [
        'Фрирен',
        'Shingeki no Kyojin',
        'Dropped one',
      ]);
      final f = c.titles.first;
      expect(f.status, ListStatus.current);
      expect(f.favorite, isTrue);
      expect(f.score, 9.1);
      expect(f.note!.verdict, 'recommend');
      expect(f.note!.summary, 'Тёплая и грустная');
      expect(f.note!.moments.single, (3, '12:30', 'Цветы'));
    });

    test('cached for an hour', () async {
      final r = repo();
      await r.catalog('yuki');
      final n = github.apiRequests;
      now = now.add(const Duration(minutes: 59));
      await r.catalog('yuki');
      expect(github.apiRequests, n, reason: 'из кэша');

      github.userGists['yuki'] = {ShareCodec.fileName: catalogJson(count: 1)};
      now = now.add(const Duration(minutes: 2));
      final fresh = await r.catalog('yuki');
      expect(github.apiRequests, greaterThan(n));
      expect(fresh.titles, hasLength(1));
    });

    test('rate limit with an old cache: the cache; without — error', () async {
      final r = repo();
      await r.catalog('yuki');
      now = now.add(const Duration(hours: 2));
      github.rateLimited = true;
      expect((await r.catalog('yuki')).titles, hasLength(3));
      await expectLater(
        r.catalog('nocatalog'),
        throwsA(
          isA<GitHubException>().having(
            (e) => e.kind,
            'kind',
            GitHubErrorKind.rateLimited,
          ),
        ),
      );
    });

    test('friend stopped sharing: clear error', () async {
      final r = repo();
      await r.catalog('yuki');
      github.userGists.remove('yuki');
      now = now.add(const Duration(hours: 2));
      await expectLater(
        r.catalog('yuki', force: true),
        throwsA(
          isA<GitHubException>().having(
            (e) => e.message,
            'message',
            contains('больше не показывает'),
          ),
        ),
      );
    });
  });
}
