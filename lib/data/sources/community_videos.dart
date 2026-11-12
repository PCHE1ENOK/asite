import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cache/app_database.dart';
import 'video_source.dart';
import 'youtube_match.dart';

/// Раздел вкладки «Сообщество»: ролики, которые делают зрители.
enum CommunitySection {
  edits('Эдиты', 'AMV'),
  reviews('Обзоры', 'review'),
  funny('Смешные моменты', 'funny moments');

  const CommunitySection(this.label, this.query);

  final String label;

  /// Что добавляется к поисковому запросу.
  final String query;
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
/// Квота: `search.list` стоит 100 единиц. Результат кэшируется на сутки
/// (пустой — на 6 часов), и каждый запрос (раздел + тайтл) уходит в сеть
/// не чаще раза в сутки на устройство.
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

  String _key(CommunitySection s, String? title) =>
      'yt:community:${s.name}:${title?.toLowerCase() ?? '*'}:${regionCode ?? ''}';

  String _day() {
    final d = _now().toUtc();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Ролики раздела; [title] — название тайтла (`null` — общий раздел).
  /// [showAdult] — «Показывать 18+» из настроек.
  Future<CommunityResult> find(
    CommunitySection section, {
    String? title,
    bool showAdult = true,
  }) async {
    if (!isConfigured) return const CommunityNotConfigured();
    final key = _key(section, title);
    final cached = await _db.entry(key);
    List<Map<String, dynamic>>? items;
    if (cached != null) {
      final list = (jsonDecode(cached.payload) as List)
          .cast<Map<String, dynamic>>();
      final age = _now().difference(cached.updatedAt);
      if (age < (list.isEmpty ? emptyTtl : ttl)) items = list;
      // Кэш устарел, но сегодня уже искали — новый поиск только завтра.
      if (items == null && await _searchedToday(key)) items = list;
    } else if (await _searchedToday(key)) {
      return const CommunityQuotaExceeded();
    }
    if (items == null) {
      try {
        items = await _search(section, title);
      } on _Quota {
        // Квота кончилась — до завтра этот поиск не повторяем.
        await _db.putSetting('$key:day', _day());
        return const CommunityQuotaExceeded();
      } on Object {
        return const CommunityFailed();
      }
      await _db.putSetting('$key:day', _day());
      await _db.putEntry(key, jsonEncode(items), _now());
    }
    return CommunityLoaded([
      for (final i in items)
        if (showAdult || !(i['adult'] as bool? ?? false))
          EmbeddedVideo(
            sourceId: 'youtube',
            videoId: i['id'] as String,
            title: i['title'] as String,
            channel: i['channel'] as String,
            thumbnail: i['thumb'] as String?,
            isCommunity: true,
          ),
    ]);
  }

  Future<bool> _searchedToday(String key) async =>
      await _db.setting('$key:day') == _day();

  /// Поиск и проверка роликов; в кэш попадают только прошедшие проверку.
  Future<List<Map<String, dynamic>>> _search(
    CommunitySection section,
    String? title,
  ) async {
    final search = await _get('search', {
      'part': 'snippet',
      'type': 'video',
      'q': title == null ? 'anime ${section.query}' : '$title ${section.query}',
      'maxResults': '25',
      'safeSearch': 'strict',
      'videoEmbeddable': 'true',
      'videoSyndicated': 'true',
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
      });
    }
    return result;
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
