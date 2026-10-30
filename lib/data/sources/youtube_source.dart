import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cache/app_database.dart';
import '../models/anime.dart';
import 'video_source.dart';

/// Официальный канал правообладателя на YouTube.
class OfficialChannel {
  const OfficialChannel(this.handle, this.name);

  /// @-имя канала; id канала узнаётся через API и кэшируется.
  final String handle;
  final String name;
}

/// Официальные бесплатные видео правообладателей на YouTube.
///
/// Поиск — YouTube Data API v3 (`channels.list` по @-имени,
/// `search.list` по каналу). Воспроизведение — только официальный
/// встраиваемый плеер YouTube; прямые потоки не используются.
/// `search.list` стоит 100 единиц квоты из 10 000 в сутки, поэтому
/// результаты кэшируются на [ttl].
class YouTubeSource implements VideoSource {
  YouTubeSource({
    required this.apiKey,
    required this._db,
    http.Client? httpClient,
    this.channels = defaultChannels,
    this.regionCode,
    this.ttl = const Duration(days: 3),
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _now = clock ?? DateTime.now;

  final String apiKey;
  final AppDatabase _db;
  final http.Client _http;
  final List<OfficialChannel> channels;

  /// Страна пользователя (ISO 3166-1): ролики, недоступные в регионе,
  /// не попадают в выдачу.
  final String? regionCode;
  final Duration ttl;
  final DateTime Function() _now;

  /// Каналы, которые выкладывают аниме бесплатно и официально.
  static const defaultChannels = [
    OfficialChannel('@MuseAsia', 'Muse Asia'),
    OfficialChannel('@AniOneAsia', 'Ani-One Asia'),
  ];

  static final _api = Uri.parse('https://www.googleapis.com/youtube/v3/');

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<List<EmbeddedVideo>> find(AnimeDetails title) async {
    if (!isConfigured) return const [];
    final result = <EmbeddedVideo>[];
    for (final channel in channels) {
      try {
        result.addAll(await _search(channel, title));
      } on Object {
        // Нет сети, квота или ошибка API — этот канал пропускаем.
      }
    }
    // По одному ролику на серию; ролики без номера — только для фильмов.
    final byEpisode = <int, EmbeddedVideo>{};
    final withoutNumber = <EmbeddedVideo>[];
    for (final v in result) {
      if (v.episode != null) {
        byEpisode.putIfAbsent(v.episode!, () => v);
      } else {
        withoutNumber.add(v);
      }
    }
    final episodes = byEpisode.keys.toList()..sort();
    return [
      for (final e in episodes) byEpisode[e]!,
      if (title.anime.format == 'MOVIE' && byEpisode.isEmpty)
        ...withoutNumber.take(1),
    ];
  }

  Future<List<EmbeddedVideo>> _search(
    OfficialChannel channel,
    AnimeDetails title,
  ) async {
    final key = 'yt:${channel.handle}:${title.id}:${regionCode ?? ''}';
    final cached = await _db.entry(key);
    List<Map<String, dynamic>> items;
    if (cached != null && _now().difference(cached.updatedAt) < ttl) {
      items = (jsonDecode(cached.payload) as List).cast<Map<String, dynamic>>();
    } else {
      final channelId = await _channelId(channel);
      if (channelId == null) return const [];
      final json = await _get('search', {
        'part': 'snippet',
        'type': 'video',
        'videoEmbeddable': 'true',
        'channelId': channelId,
        'q': title.anime.title.romaji ?? title.anime.title.preferred,
        'maxResults': '50',
        'regionCode': ?regionCode,
      });
      items = (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      await _db.putEntry(key, jsonEncode(items), _now());
    }
    return [
      for (final item in items) ?parseSearchItem(item, channel.name, title),
    ];
  }

  /// Id канала по @-имени (кэшируется надолго, стоит 1 единицу квоты).
  Future<String?> _channelId(OfficialChannel channel) async {
    final key = 'yt:channel:${channel.handle}';
    final cached = await _db.entry(key);
    if (cached != null) return cached.payload;
    final json = await _get('channels', {
      'part': 'id',
      'forHandle': channel.handle,
    });
    final items = json['items'] as List? ?? const [];
    final id = items.isEmpty ? null : (items.first as Map)['id'] as String?;
    if (id != null) await _db.putEntry(key, id, _now());
    return id;
  }

  Future<Map<String, dynamic>> _get(
    String method,
    Map<String, String> params,
  ) async {
    final uri = _api
        .resolve(method)
        .replace(queryParameters: {...params, 'key': apiKey});
    final response = await _http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('YouTube API ${response.statusCode}', uri);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  /// Ролик из ответа `search.list`, если его название относится к тайтлу.
  static EmbeddedVideo? parseSearchItem(
    Map<String, dynamic> item,
    String channel,
    AnimeDetails title,
  ) {
    final videoId = (item['id'] as Map?)?['videoId'] as String?;
    final snippet = item['snippet'] as Map?;
    final videoTitle = _unescape(snippet?['title'] as String? ?? '');
    if (videoId == null || !matchesTitle(videoTitle, title)) return null;
    final thumbs = snippet?['thumbnails'] as Map?;
    return EmbeddedVideo(
      sourceId: 'youtube',
      videoId: videoId,
      title: videoTitle,
      channel: channel,
      episode: episodeNumber(videoTitle),
      thumbnail:
          ((thumbs?['medium'] ?? thumbs?['default']) as Map?)?['url']
              as String?,
    );
  }

  /// Название ролика содержит одно из названий тайтла (от 4 символов).
  static bool matchesTitle(String videoTitle, AnimeDetails title) {
    final v = _norm(videoTitle);
    final names = [
      title.anime.title.romaji,
      title.anime.title.english,
      title.anime.title.native,
      ...title.synonyms,
    ].whereType<String>().map(_norm).where((n) => n.length >= 4);
    return names.any(v.contains);
  }

  /// Номер серии из названия: «Episode 5», «EP05», «Ep. 12», «#3».
  static int? episodeNumber(String videoTitle) {
    final m = RegExp(
      r'(?:episode|ep\.?|эпизод|серия|#)\s*0*(\d{1,4})\b',
      caseSensitive: false,
    ).firstMatch(videoTitle);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
