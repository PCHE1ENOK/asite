import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../models/anime.dart';
import 'shikimori_client.dart';

/// Русское название и оценка тайтла из Shikimori (для списков).
class ShikiInfo {
  const ShikiInfo({this.title, this.score});

  final String? title;

  /// Оценка 0–10; `null` — на Shikimori оценки нет.
  final double? score;

  Map<String, dynamic> toJson() => {'ru': title, 'score': score};

  static ShikiInfo fromJson(Map<String, dynamic> j) => ShikiInfo(
    title: j['ru'] as String?,
    score: (j['score'] as num?)?.toDouble(),
  );
}

/// Русское название, описание и оценка тайтла из Shikimori.
class RussianDetails {
  const RussianDetails({this.title, this.description, this.score});

  final String? title;
  final String? description;
  final double? score;

  bool get isEmpty => title == null && description == null && score == null;
}

/// Русские названия, описания и оценки: берём из Shikimori (AniList
/// русского не отдаёт; оценку показываем по Shikimori, если она там есть).
///
/// Сопоставление с AniList — по id MyAnimeList (`idMal`: у Shikimori те же
/// id), без него — поиском по названию с проверкой года. Кэш — 7 дней в
/// базе, в том числе «русского нет»; ошибки сети не кэшируются.
class RussianTextRepository {
  RussianTextRepository({
    required this.db,
    required this.client,
    this.ttl = const Duration(days: 7),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AppDatabase db;
  final ShikimoriClient client;
  final Duration ttl;
  final DateTime Function() _now;

  static String _titleKey(int id) => 'shiki:info:$id';
  static String _detailsKey(int id) => 'shiki:details2:$id';

  Future<String?> _fresh(String key) async {
    final e = await db.entry(key);
    if (e == null || _now().difference(e.updatedAt) >= ttl) return null;
    return e.payload;
  }

  /// Русские названия и оценки для списка тайтлов (каталог, списки,
  /// поиск): один запрос на 50 тайтлов. В ответе — только найденные.
  Future<Map<int, ShikiInfo>> titles(List<Anime> items) async {
    final result = <int, ShikiInfo>{};
    final need = <Anime>[];
    for (final a in items) {
      final cached = await _fresh(_titleKey(a.id));
      if (cached != null) {
        final info = ShikiInfo.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
        if (info.title != null || info.score != null) result[a.id] = info;
      } else if (a.idMal != null) {
        need.add(a);
      }
    }
    for (var i = 0; i < need.length; i += 50) {
      final chunk = need.sublist(i, (i + 50).clamp(0, need.length));
      final List<ShikiAnime> found;
      try {
        found = await client.byIds([for (final a in chunk) a.idMal!]);
      } on ShikimoriException {
        continue; // Без сети — английские названия, кэш не трогаем.
      }
      final byMal = {for (final s in found) s.id: s};
      for (final a in chunk) {
        final s = byMal[a.idMal];
        final info = ShikiInfo(title: s?.russian, score: s?.score);
        await db.putEntry(_titleKey(a.id), jsonEncode(info.toJson()), _now());
        if (s != null && (s.russian != null || s.score != null)) {
          result[a.id] = info;
        }
      }
    }
    return result;
  }

  /// Русское название и описание для карточки тайтла; `null` — Shikimori
  /// недоступен (показываем английское, в кэш не пишем).
  Future<RussianDetails?> details(AnimeDetails d) async {
    final cached = await _fresh(_detailsKey(d.id));
    if (cached != null) {
      final j = jsonDecode(cached) as Map<String, dynamic>;
      return RussianDetails(
        title: j['title'] as String?,
        description: j['description'] as String?,
        score: (j['score'] as num?)?.toDouble(),
      );
    }
    final ShikiAnime? found;
    try {
      final mal = d.anime.idMal ?? (await _match(d))?.id;
      found = mal == null ? null : await client.details(mal);
    } on ShikimoriException {
      return null;
    }
    final r = RussianDetails(
      title: found?.russian,
      description: found?.description,
      score: found?.score,
    );
    final now = _now();
    await db.putEntry(
      _detailsKey(d.id),
      jsonEncode({
        'title': r.title,
        'description': r.description,
        'score': r.score,
      }),
      now,
    );
    await db.putEntry(
      _titleKey(d.id),
      jsonEncode(ShikiInfo(title: r.title, score: r.score).toJson()),
      now,
    );
    return r;
  }

  /// Тайтл Shikimori по названию и году (если у AniList нет id MAL).
  Future<ShikiAnime?> _match(AnimeDetails d) async {
    final t = d.anime.title;
    final names = {
      for (final n in [t.romaji, t.english, ...d.synonyms])
        if (n != null && n.trim().isNotEmpty) norm(n),
    };
    final year = d.anime.seasonYear ?? d.startDate?.year;
    for (final q in [t.romaji, t.english].nonNulls) {
      for (final s in await client.search(q)) {
        final sameYear = year == null || s.year == null || s.year == year;
        if (sameYear && s.name != null && names.contains(norm(s.name!))) {
          return s;
        }
      }
    }
    return null;
  }

  @visibleForTesting
  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

/// Данные Shikimori в памяти (русское название, оценка): у каждого
/// тайтла свой [ValueNotifier], и при подгрузке пересобираются только его
/// подпись и бейдж, а не вся сетка.
class ShikimoriData {
  ShikimoriData(this.repository);

  final RussianTextRepository repository;
  final _info = <int, ValueNotifier<ShikiInfo?>>{};
  final _requested = <int>{};

  ValueListenable<ShikiInfo?> of(int id) =>
      _info.putIfAbsent(id, () => ValueNotifier(null));

  void put(int id, ShikiInfo? info) {
    if (info != null && (info.title != null || info.score != null)) {
      (of(id) as ValueNotifier<ShikiInfo?>).value = info;
    }
  }

  /// Подгружает данные для показанных тайтлов (повторно не просит).
  Future<void> prefetch(Iterable<Anime> items) async {
    final need = [
      for (final a in items)
        if (_requested.add(a.id)) a,
    ];
    if (need.isEmpty) return;
    final found = await repository.titles(need);
    found.forEach(put);
  }
}
