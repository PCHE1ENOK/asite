import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cache/app_database.dart';
import 'video_source.dart';
import 'youtube_match.dart';

/// Раздел вкладки «Сообщество»: ролики, которые делают зрители.
/// Поиск только по-русски; у раздела может быть несколько запросов.
enum CommunitySection {
  retell('Пересказ аниме', ['Переозвучка {t}', '{t} за 15 минут']),
  edits('Эдиты', ['{t} AMV']),
  reviews('Обзоры', ['{t} обзор']),
  funny('Смешные моменты', ['{t} смешные моменты']);

  const CommunitySection(this.label, this.queries);

  final String label;

  /// Шаблоны запросов: `{t}` — название тайтла.
  final List<String> queries;

  /// Запросы раздела для тайтла [title].
  List<String> queriesFor(String title) => [
    for (final q in queries) q.replaceAll('{t}', title),
  ];
}

/// Ответ вкладки «Сообщество».
sealed class CommunityResult {
  const CommunityResult();
}

class CommunityLoaded extends CommunityResult {
  const CommunityLoaded(this.videos, {this.quotaHit = false});

  final List<EmbeddedVideo> videos;

  /// Квота кончилась, показан прошлый кэш (над сеткой — предупреждение).
  final bool quotaHit;
}

/// Нет ключа YouTube.
class CommunityNotConfigured extends CommunityResult {
  const CommunityNotConfigured();
}

/// Квота YouTube Data API исчерпана (или наш дневной лимит поисков).
class CommunityQuotaExceeded extends CommunityResult {
  const CommunityQuotaExceeded();
}

class CommunityFailed extends CommunityResult {
  const CommunityFailed();
}

/// Ролики сообщества с YouTube по тайтлу: пересказы, эдиты, обзоры,
/// смешные моменты. Только русскоязычные.
///
/// Поиск — `search.list` со строгим безопасным поиском, русским языком
/// (`relevanceLanguage=ru`), только встраиваемые и доступные вне
/// youtube.com ролики. Каждый найденный ролик проверяется `videos.list`
/// (1 единица на запрос): отбрасываются ролики с возрастным ограничением,
/// недоступные в регионе, без встраивания и не на русском (нет русского
/// языка в метаданных и кириллицы в названии). Без «Показывать 18+» —
/// ещё и ролики с пометками 18+ в названии или тегах.
///
/// Квота: `search.list` стоит 100 единиц. Результат каждого запроса
/// кэшируется на сутки (пустой — на 6 часов), и каждый запрос уходит в
/// сеть не чаще раза в сутки на устройство.
class CommunityVideos {
  CommunityVideos({
    required this.apiKey,
    required this._db,
    http.Client? httpClient,
    this.regionCode,
    this.ttl = const Duration(hours: 24),
    this.emptyTtl = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _now = clock ?? DateTime.now;

  final String apiKey;
  final AppDatabase _db;
  final http.Client _http;
  final String? regionCode;
  final Duration ttl;
  final Duration emptyTtl;
  final DateTime Function() _now;

  static final _api = Uri.parse('https://www.googleapis.com/youtube/v3/');

  /// Пометки «для взрослых» в названии или тегах ролика.
  static final adultMarks = RegExp(
    r'(?<![\p{L}\p{N}])(?:18\s?\+|r-?18|nsfw|hentai|ecchi|uncensored|'
    r'for adults only)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final _cyrillic = RegExp('[\\u0400-\\u04FF]');

  bool get isConfigured => apiKey.isNotEmpty;

  String _key(String query) =>
      'yt:community:ru:${query.toLowerCase()}:${regionCode ?? ''}';

  String _day() {
    final d = _now().toUtc();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Ролики раздела по тайтлу [title] (русское название, иначе ромадзи).
  /// [showAdult] — «Показывать 18+» из настроек.
  Future<CommunityResult> find(
    CommunitySection section, {
    required String title,
    bool showAdult = true,
  }) async {
    if (!isConfigured) return const CommunityNotConfigured();
    final results = [for (final q in section.queriesFor(title)) await _find(q)];
    final lists = [
      for (final r in results)
        if (r case (final List<Map<String, dynamic>> l, _)) l,
    ];
    final quotaHit = results.any(
      (r) => switch (r) {
        _Quota() || (_, true) => true,
        _ => false,
      },
    );
    if (lists.isEmpty) {
      return quotaHit
          ? const CommunityQuotaExceeded()
          : const CommunityFailed();
    }
    // Вперемешку по запросам, без повторов.
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (var i = 0; lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length && seen.add(l[i]['id'] as String)) merged.add(l[i]);
      }
    }
    return CommunityLoaded([
      for (final i in merged)
        if (showAdult || !(i['adult'] as bool? ?? false))
          EmbeddedVideo(
            sourceId: 'youtube',
            videoId: i['id'] as String,
            title: i['title'] as String,
            channel: i['channel'] as String,
            thumbnail: i['thumb'] as String?,
            isCommunity: true,
            duration: switch (i['seconds']) {
              final int s => Duration(seconds: s),
              _ => null,
            },
            category: section.label,
          ),
    ], quotaHit: quotaHit);
  }

  /// Один запрос: `(список, квота кончилась — показан старый кэш)`,
  /// [_Quota] (квоты нет и кэша нет) или [_Failed].
  Future<Object> _find(String query) async {
    final key = _key(query);
    final cached = await _db.entry(key);
    List<Map<String, dynamic>>? stale;
    if (cached != null) {
      final list = (jsonDecode(cached.payload) as List)
          .cast<Map<String, dynamic>>();
      final age = _now().difference(cached.updatedAt);
      if (age < (list.isEmpty ? emptyTtl : ttl)) return (list, false);
      // Кэш устарел, но сегодня уже искали — новый поиск только завтра.
      if (await _searchedToday(key)) return (list, false);
      stale = list;
    } else if (await _searchedToday(key)) {
      return const _Quota();
    }
    final List<Map<String, dynamic>> items;
    try {
      items = await _search(query);
    } on _Quota {
      // Квота кончилась — до завтра этот поиск не повторяем.
      await _db.putSetting('$key:day', _day());
      return stale == null ? const _Quota() : (stale, true);
    } on Object {
      return stale == null ? const _Failed() : (stale, false);
    }
    await _db.putSetting('$key:day', _day());
    await _db.putEntry(key, jsonEncode(items), _now());
    return (items, false);
  }

  Future<bool> _searchedToday(String key) async =>
      await _db.setting('$key:day') == _day();

  /// Поиск и проверка роликов; в кэш попадают только прошедшие проверку.
  Future<List<Map<String, dynamic>>> _search(String query) async {
    final search = await _get('search', {
      'part': 'snippet',
      'type': 'video',
      'q': query,
      'maxResults': '25',
      'safeSearch': 'strict',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
      'relevanceLanguage': 'ru',
      'regionCode': ?regionCode,
    });
    final ids = [
      for (final i in (search['items'] as List? ?? const []).cast<Map>())
        if ((i['id'] as Map?)?['videoId'] case final String id) id,
    ];
    if (ids.isEmpty) return const [];
    final details = await _get('videos', {
      'part': 'snippet,contentDetails,status',
      'id': ids.join(','),
    });
    final byId = {
      for (final v in (details['items'] as List? ?? const []).cast<Map>())
        v['id'] as String: v,
    };
    final result = <Map<String, dynamic>>[];
    for (final id in ids) {
      final v = byId[id];
      if (v == null || !isAllowed(v, regionCode)) continue;
      final s = v['snippet'] as Map? ?? const {};
      if (!isRussian(s)) continue;
      final name = YouTubeMatch.unescape(s['title'] as String? ?? '');
      final tags = (s['tags'] as List?)?.cast<String>() ?? const [];
      final thumbs = s['thumbnails'] as Map?;
      final content = v['contentDetails'] as Map? ?? const {};
      result.add({
        'id': id,
        'title': name,
        'channel': s['channelTitle'] as String? ?? '',
        'thumb':
            ((thumbs?['medium'] ?? thumbs?['default']) as Map?)?['url']
                as String?,
        'adult': adultMarks.hasMatch([name, ...tags].join(' ')),
        'seconds': parseDuration(content['duration'] as String?)?.inSeconds,
      });
    }
    return result;
  }

  /// Ролик на русском: русский язык в метаданных
  /// (`defaultAudioLanguage` / `defaultLanguage`) или кириллица в названии.
  static bool isRussian(Map snippet) {
    for (final k in ['defaultAudioLanguage', 'defaultLanguage']) {
      final lang = snippet[k];
      if (lang is String && lang.toLowerCase().startsWith('ru')) return true;
    }
    return _cyrillic.hasMatch(snippet['title'] as String? ?? '');
  }

  /// ISO 8601 `PT1H2M3S` → длительность; прямые эфиры (`P0D`) — `null`.
  static Duration? parseDuration(String? iso) {
    final m = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$')
        .firstMatch(iso ?? '');
    if (m == null) return null;
    int g(int i) => int.parse(m[i] ?? '0');
    final d = Duration(days: g(1), hours: g(2), minutes: g(3), seconds: g(4));
    return d == Duration.zero ? null : d;
  }

  /// Когда YouTube обновит квоту: полночь по тихоокеанскому времени
  /// (PST UTC−8, летом PDT UTC−7), в местном времени устройства.
  static DateTime quotaResetAfter(DateTime now) {
    final utc = now.toUtc();
    final offset = _isPacificDst(utc) ? 7 : 8;
    final pacific = utc.subtract(Duration(hours: offset));
    final nextMidnight = DateTime.utc(
      pacific.year,
      pacific.month,
      pacific.day + 1,
    );
    // Полночь следующих тихоокеанских суток — в UTC, затем в местное
    // (летнее время переключается в 2:00, полночь — по прежнему смещению).
    return nextMidnight.add(Duration(hours: offset)).toLocal();
  }

  /// Летнее время в США: со 2-го воскресенья марта 2:00 до 1-го
  /// воскресенья ноября 2:00 (по местному).
  static bool _isPacificDst(DateTime utc) {
    DateTime sunday(int month, int nth) {
      var d = DateTime.utc(utc.year, month);
      while (d.weekday != DateTime.sunday) {
        d = d.add(const Duration(days: 1));
      }
      return d.add(Duration(days: 7 * (nth - 1)));
    }

    final start = sunday(3, 2).add(const Duration(hours: 10)); // 2:00 PST
    final end = sunday(11, 1).add(const Duration(hours: 9)); // 2:00 PDT
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  /// Ролик можно показать: без возрастного ограничения, встраивается,
  /// публичный и доступен в регионе.
  static bool isAllowed(Map v, String? region) {
    final content = v['contentDetails'] as Map? ?? const {};
    final status = v['status'] as Map? ?? const {};
    final rating = content['contentRating'] as Map?;
    if (rating?['ytRating'] == 'ytAgeRestricted') return false;
    if (status['embeddable'] != true) return false;
    if ((status['privacyStatus'] ?? 'public') != 'public') return false;
    final rr = content['regionRestriction'] as Map?;
    if (region != null && rr != null) {
      final allowed = (rr['allowed'] as List?)?.cast<String>();
      final blocked = (rr['blocked'] as List?)?.cast<String>();
      if (allowed != null && !allowed.contains(region)) return false;
      if (blocked?.contains(region) ?? false) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _get(
    String method,
    Map<String, String> params,
  ) async {
    final uri = _api
        .resolve(method)
        .replace(queryParameters: {...params, 'key': apiKey});
    final res = await _http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 403 &&
        RegExp('quotaExceeded|dailyLimitExceeded|rateLimitExceeded')
            .hasMatch(res.body)) {
      throw const _Quota();
    }
    if (res.statusCode != 200) {
      throw http.ClientException('YouTube API ${res.statusCode}', uri);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}

class _Quota implements Exception {
  const _Quota();
}

class _Failed {
  const _Failed();
}
