import 'dart:convert';

import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/models/favorite.dart';
import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/data/share/share_codec.dart';
import 'package:anime_viewer/data/shikimori/russian_text.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 31, 12);

Anime anime(int id, {bool adult = false, int? avg = 80}) => Anime(
  id: id,
  isAdult: adult,
  averageScore: avg,
  format: 'TV',
  seasonYear: 2024,
  episodes: 12,
  coverImage: const CoverImage(large: 'https://img/l.jpg', color: '#7a2e4a'),
  title: AnimeTitle(romaji: 'R$id', english: 'E$id'),
);

Map<String, dynamic> build() => ShareCodec.build(
  owner: 'Юки',
  now: now,
  entries: [
    LibraryEntry(
      mediaId: 1,
      status: ListStatus.current,
      progress: 5,
      updatedAt: now,
    ),
    LibraryEntry(mediaId: 2, status: ListStatus.dropped, updatedAt: now),
    LibraryEntry(
      mediaId: 9,
      status: ListStatus.planning,
      updatedAt: now,
      deleted: true,
    ),
  ],
  favorites: [
    Favorite(mediaId: 1, updatedAt: now),
    Favorite(mediaId: 3, updatedAt: now), // не в списках
    Favorite(mediaId: 8, updatedAt: now, deleted: true),
  ],
  notes: [
    TitleNote(
      mediaId: 2,
      updatedAt: now,
      verdict: NoteVerdict.notRecommend,
      summary: 'Сильное начало',
      liked: 'Первая серия',
      dropReasons: const ['Затянуто'],
      dropText: 'После 4-й серии',
      moments: const [
        NoteMoment(
          episode: 4,
          timecode: Duration(minutes: 17, seconds: 40),
          text: 'Погоня',
        ),
      ],
    ),
  ],
  summaries: {
    1: anime(1),
    2: anime(2, adult: true),
    3: anime(3, avg: null),
    8: anime(8),
    9: anime(9),
  },
  shikimori: {1: const ShikiInfo(title: 'Дандадан', score: 8.44)},
);

void main() {
  test('all titles: lists, favorites, notes; deleted ones are left out', () {
    final j = build();
    expect(j['version'], 1);
    expect(j['owner'], 'Юки');
    final titles = {for (final t in j['titles'] as List) t['id']: t};
    expect(titles.keys, [1, 2, 3]);

    final t1 = titles[1];
    expect(t1['title'], {'ru': 'Дандадан', 'en': 'E1', 'romaji': 'R1'});
    expect(t1['status'], 'CURRENT');
    expect(t1['progress'], 5);
    expect(t1['favorite'], isTrue);
    expect(t1['score'], {'value': 8.4, 'source': 'shikimori'});
    expect(t1['cover'], 'https://img/l.jpg');

    expect(titles[3]['favorite'], isTrue);
    expect(titles[3].containsKey('status'), isFalse);
    expect(titles[3].containsKey('score'), isFalse, reason: 'no score — none');
  });

  test('18+ and notes with all fields are included', () {
    final t2 = {for (final t in build()['titles'] as List) t['id']: t}[2];
    expect(t2['adult'], isTrue);
    expect(t2['score'], {'value': 8.0, 'source': 'anilist'});
    expect(t2['note'], {
      'verdict': 'not',
      'summary': 'Сильное начало',
      'liked': 'Первая серия',
      'dropReasons': ['Затянуто'],
      'dropText': 'После 4-й серии',
      'moments': [
        {'episode': 4, 'time': '17:40', 'text': 'Погоня'},
      ],
    });
  });

  test('no token, client id, keys or GitHub login in share.json', () {
    final text = ShareCodec.encode(build());
    for (final secret in [
      'token',
      'Bearer',
      'ghp_',
      'gho_',
      'Ov23',
      'client',
      'apiKey',
      'key=',
      'AIza',
      'login',
      'gist',
      'anime-viewer-library',
    ]) {
      expect(
        text.toLowerCase(),
        isNot(contains(secret.toLowerCase())),
        reason: secret,
      );
    }
    // Только поля формата.
    final j = jsonDecode(text) as Map<String, dynamic>;
    expect(j.keys.toSet(), {'version', 'owner', 'updatedAt', 'titles'});
    const allowed = {
      'id',
      'title',
      'cover',
      'coverColor',
      'format',
      'year',
      'episodes',
      'score',
      'status',
      'progress',
      'favorite',
      'adult',
      'updatedAt',
      'trailer',
      'note',
    };
    for (final t in j['titles'] as List) {
      expect(allowed.containsAll((t as Map).keys), isTrue, reason: '${t.keys}');
    }
  });
}
