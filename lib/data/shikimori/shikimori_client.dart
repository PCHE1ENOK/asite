import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Тайтл Shikimori: только то, что нужно для русского названия и
/// описания. `id` Shikimori совпадает с id MyAnimeList.
class ShikiAnime {
  const ShikiAnime({
    required this.id,
    this.russian,
    this.name,
    this.year,
    this.description,
  });

  final int id;
  final String? russian;

  /// Название латиницей (ромадзи).
  final String? name;

  /// Год начала показа (`aired_on`).
  final int? year;

  /// Описание без разметки Shikimori (только в подробностях).
  final String? description;

  static ShikiAnime? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! int) return null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final aired = text(j['aired_on']);
    final raw = text(j['description']);
    return ShikiAnime(
      id: id,
      russian: text(j['russian']),
      name: text(j['name']),
      year: aired == null ? null : int.tryParse(aired.split('-').first),
      description: raw == null ? null : plainDescription(raw),
    );
  }

  /// Убирает разметку Shikimori: `[character=1]Имя[/character]` → «Имя»,
  /// `[[Имя]]` → «Имя», `[i]`, `[b]`, `[url=…]`, `[spoiler]` и т. п.
  static String plainDescription(String s) => s
      .replaceAllMapped(RegExp(r'\[\[([^\]]*)\]\]'), (m) => m[1]!)
      .replaceAll(
        RegExp(r'\[/?[a-z_]+(?:=[^\]]*)?\]', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Ошибка Shikimori (сеть, лимит запросов, ответ не тот).
class ShikimoriException implements Exception {
  const ShikimoriException(this.message);

  final String message;

  @override
  String toString() => 'ShikimoriException: $message';
}

/// Открытый API Shikimori (shikimori.one/api): бесплатно, без ключа.
/// Shikimori просит осмысленный User-Agent и не больше 5 запросов в
/// секунду — запросы идут по одному с паузой [minInterval].
class ShikimoriClient {
  ShikimoriClient({
    http.Client? httpClient,
    this.minInterval = const Duration(milliseconds: 250),
  }) : _http = httpClient ?? http.Client();

  static const base = 'https://shikimori.one/api/';

  /// Название приложения для Shikimori (без личных данных).
  static const userAgent = 'AnimeViewer/1.0 (Flutter; personal anime catalog)';

  final http.Client _http;
  final Duration minInterval;
  Future<void> _queue = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Краткие записи по id MyAnimeList (до 50 за запрос).
  Future<List<ShikiAnime>> byIds(List<int> malIds) async {
    if (malIds.isEmpty) return const [];
    final json = await _get('animes', {
      'ids': malIds.take(50).join(','),
      'limit': '50',
    });
    return _list(json);
  }

  /// Поиск по названию (для тайтлов без id MyAnimeList).
  Future<List<ShikiAnime>> search(String query) async =>
      _list(await _get('animes', {'search': query, 'limit': '10'}));

  /// Подробности: русское название и описание. `null` — нет такого.
  Future<ShikiAnime?> details(int id) async {
    try {
      return ShikiAnime.fromJson(await _get('animes/$id', const {}));
    } on _NotFound {
      return null;
    }
  }

  static List<ShikiAnime> _list(Object? json) => [
    if (json is List)
      for (final j in json) ?ShikiAnime.fromJson(j),
  ];

  Future<Object?> _get(String path, Map<String, String> params) {
    final done = _queue.then((_) => _send(path, params));
    _queue = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<Object?> _send(String path, Map<String, String> params) async {
    final wait = minInterval - DateTime.now().difference(_last);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final uri = Uri.parse(base)
        .resolve(path)
        .replace(queryParameters: params.isEmpty ? null : params);
    final http.Response res;
    try {
      res = await _http
          .get(uri, headers: const {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      throw ShikimoriException('сеть: $e');
    }
    if (res.statusCode == 404) throw const _NotFound();
    if (res.statusCode != 200) {
      throw ShikimoriException('HTTP ${res.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw const ShikimoriException('ответ не JSON');
    }
  }
}

class _NotFound extends ShikimoriException {
  const _NotFound() : super('не найдено');
}
