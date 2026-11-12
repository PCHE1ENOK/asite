import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cache/app_database.dart';
import 'video_source.dart';
import 'youtube_match.dart';

/// Раздел вкладки «Сообщество»: ролики, которые делают зрители.
enum CommunitySection {
  edits('Эдиты', 'AMV', 'AMV'),
  reviews('Обзоры', 'review', 'обзор'),
  funny('Смешные моменты', 'funny moments', 'смешные моменты');

  const CommunitySection(this.label, this.query, this.ruQuery);

  final String label;

  /// Что добавляется к английскому поисковому запросу.
  final String query;

  /// То же для русского запроса.
  final String ruQuery;
}

/// Язык поискового запроса «Сообщества».
enum CommunityLanguage {
  en('ENG'),
  ru('RU');

  const CommunityLanguage(this.label);

  /// Метка на карточке ролика.
  final String label;
}

/// Ответ вкладки «Сообщество».
sealed class CommunityResult {
  const CommunityResult();
}

class CommunityLoaded extends CommunityResult {
  const CommunityLoaded(this.videos);

  final List<EmbeddedVideo> videos;
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

/// Ролики сообщества с YouTube: эдиты, обзоры, смешные моменты.
///
/// Поиск — `search.list` со строгим безопасным поиском, только
/// встраиваемые и доступные вне youtube.com ролики. Каждый найденный ролик
/// проверяется `videos.list` (1 единица на 50 роликов): отбрасываются
/// ролики с возрастным ограничением, недоступные в регионе и без
/// встраивания. Без «Показывать 18+» — ещё и ролики с пометками 18+ в
/// названии или тегах.
///
/// Ищется на двух языках (английский и русский запросы), у роликов —
/// метка «RU» / «ENG».
///
/// Квота: `search.list` стоит 100 единиц, на раздел — два поиска.
/// Результат кэшируется на сутки (пустой — на 6 часов), и каждый запрос
/// (язык + раздел + тайтл) уходит в сеть не чаще раза в сутки на
/// устройство.
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

  bool get isConfigured => apiKey.isNotEmpty;

  String _key(CommunityLanguage lang, CommunitySection s, String? title) =>
      'yt:community:${lang.name}:${s.name}:${title?.toLowerCase() ?? '*'}:'
      '${regionCode ?? ''}';

  String _day() {
    final d = _now().toUtc();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Ролики раздела на двух языках; [title] — название тайтла
  /// (`null` — общий раздел), [ruTitle] — русское название для русского
  /// запроса (нет — [title]). [showAdult] — «Показывать 18+» из настроек.
  ///
  /// Два поиска — английский и русский: у каждого свой кэш и своё
  /// ограничение «один раз в сутки». Ролик, найденный обоими, — один раз.
  Future<CommunityResult> find(
    CommunitySection section, {
    String? title,
    String? ruTitle,
    bool showAdult = true,
  }) async {
    if (!isConfigured) return const CommunityNotConfigured();
    final en = await _find(CommunityLanguage.en, section, title);
    final ru = await _find(CommunityLanguage.ru, section, ruTitle ?? title);
    final lists = [en, ru].whereType<List<Map<String, dynamic>>>().toList();
    if (lists.isEmpty) {
      return en is _Quota || ru is _Quota
          ? const CommunityQuotaExceeded()
          : const CommunityFailed();
    }
    // Вперемешку: английский, русский, английский… без повторов.
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
            language: i['lang'] as String?,
          ),
    ]);
  }

  /// Один запрос: список роликов, [_Quota] (квота или поиск уже был
  /// сегодня, а кэша нет) или [_Failed].
  Future<Object> _find(
    CommunityLanguage lang,
    CommunitySection section,
    String? title,
  ) async {
    final key = _key(lang, section, title);
    final cached = await _db.entry(key);
    if (cached != null) {
      final list = (jsonDecode(cached.payload) as List)
          .cast<Map<String, dynamic>>();
      final age = _now().difference(cached.updatedAt);
      if (age < (list.isEmpty ? emptyTtl : ttl)) return list;
      // Кэш устарел, но сегодня уже искали — новый поиск только завтра.
      if (await _searchedToday(key)) return list;
    } else if (await _searchedToday(key)) {
      return const _Quota();
    }
    final List<Map<String, dynamic>> items;
    try {
      items = await _search(lang, section, title);
    } on _Quota {
      // Квота кончилась — до завтра этот поиск не повторяем.
      await _db.putSetting('$key:day', _day());
      return const _Quota();
    } on Object {
      return const _Failed();
    }
    await _db.putSetting('$key:day', _day());
    await _db.putEntry(key, jsonEncode(items), _now());
    return items;
  }

  Future<bool> _searchedToday(String key) async =>
      await _db.setting('$key:day') == _day();

  /// Поиск и проверка роликов; в кэш попадают только прошедшие проверку.
  Future<List<Map<String, dynamic>>> _search(
    CommunityLanguage lang,
    CommunitySection section,
    String? title,
  ) async {
    final words = lang == CommunityLanguage.ru
        ? section.ruQuery
        : section.query;
    final search = await _get('search', {
      'part': 'snippet',
      'type': 'video',
      'q': title == null
          ? (lang == CommunityLanguage.ru ? 'аниме $words' : 'anime $words')
          : '$title $words',
      'maxResults': '25',
      'safeSearch': 'strict',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
      'relevanceLanguage': lang.name,
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
      final name = YouTubeMatch.unescape(s['title'] as String? ?? '');
      final tags = (s['tags'] as List?)?.cast<String>() ?? const [];
      final thumbs = s['thumbnails'] as Map?;
      result.add({
        'id': id,
        'title': name,
        'channel': s['channelTitle'] as String? ?? '',
        'thumb':
            ((thumbs?['medium'] ?? thumbs?['default']) as Map?)?['url']
                as String?,
        'adult': adultMarks.hasMatch([name, ...tags].join(' ')),
        'lang': languageOf(s),
      });
    }
    return result;
  }

  static final _cyrillic = RegExp('[\u0400-\u04FF]');

  /// «RU» или «ENG»: по языку из метаданных ролика (`defaultAudioLanguage`,
  /// затем `defaultLanguage`), иначе — по кириллице в названии.
  static String languageOf(Map snippet) {
    final meta =
        (snippet['defaultAudioLanguage'] ?? snippet['defaultLanguage'])
            as String?;
    if (meta != null && meta.isNotEmpty) {
      return meta.toLowerCase().startsWith('ru')
          ? CommunityLanguage.ru.label
          : CommunityLanguage.en.label;
    }
    return _cyrillic.hasMatch(snippet['title'] as String? ?? '')
        ? CommunityLanguage.ru.label
        : CommunityLanguage.en.label;
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
