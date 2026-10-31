import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cache/app_database.dart';
import '../models/anime.dart';
import 'shikimori_client.dart';

/// Русское название и описание тайтла из Shikimori.
class RussianDetails {
  const RussianDetails({this.title, this.description});

  final String? title;
  final String? description;

  bool get isEmpty => title == null && description == null;
}

/// Русские названия и описания: AniList их не отдаёт, берём из Shikimori.
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

  static String _titleKey(int id) => 'shiki:title:$id';
  static String _detailsKey(int id) => 'shiki:details:$id';

  Future<String?> _fresh(String key) async {
    final e = await db.entry(key);
    if (e == null || _now().difference(e.updatedAt) >= ttl) return null;
    return e.payload;
  }

  /// Русские названия для списка тайтлов (каталог, списки, поиск): один
  /// запрос на 50 тайтлов. В ответе — только найденные.
  Future<Map<int, String>> titles(List<Anime> items) async {
    final result = <int, String>{};
    final need = <Anime>[];
    for (final a in items) {
      final cached = await _fresh(_titleKey(a.id));
      if (cached != null) {
        if (cached.isNotEmpty) result[a.id] = cached;
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
        final ru = byMal[a.idMal]?.russian ?? '';
        await db.putEntry(_titleKey(a.id), ru, _now());
        if (ru.isNotEmpty) result[a.id] = ru;
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
    );
    final now = _now();
    await db.putEntry(
      _detailsKey(d.id),
      jsonEncode({'title': r.title, 'description': r.description}),
      now,
    );
    await db.putEntry(_titleKey(d.id), r.title ?? '', now);
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

/// Русские названия в памяти: у каждого тайтла свой [ValueNotifier], и
/// при подгрузке пересобирается только его подпись, а не вся сетка.
class RussianTitles {
  RussianTitles(this.repository);

  final RussianTextRepository repository;
  final _titles = <int, ValueNotifier<String?>>{};
  final _requested = <int>{};

  ValueListenable<String?> of(int id) =>
      _titles.putIfAbsent(id, () => ValueNotifier(null));

  void put(int id, String? title) {
    if (title != null && title.isNotEmpty) {
      (of(id) as ValueNotifier<String?>).value = title;
    }
  }

  /// Подгружает названия для показанных тайтлов (повторно не просит).
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
