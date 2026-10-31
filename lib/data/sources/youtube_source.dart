import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cache/app_database.dart';
import '../models/anime.dart';
import 'video_source.dart';
import 'youtube_match.dart';

export 'youtube_match.dart' show OfficialChannel;

/// Официальные бесплатные видео правообладателей на YouTube.
///
/// Поиск — YouTube Data API v3 (`channels.list` по @-имени,
/// `search.list` по каналу). Воспроизведение — только официальный
/// встраиваемый плеер YouTube; прямые потоки не используются.
/// `search.list` стоит 100 единиц квоты из 10 000 в сутки, поэтому
/// результаты кэшируются на [ttl]; выдача без подходящих роликов — только
/// на [emptyTtl], чтобы исправленный ключ или новая серия появились скоро.
class YouTubeSource implements VideoSource {
  YouTubeSource({
    required this.apiKey,
    required this._db,
    http.Client? httpClient,
    this.channels = defaultChannels,
    this.trailerChannels = YouTubeMatch.trailerChannels,
    this.regionCode,
    this.ttl = const Duration(days: 3),
    this.emptyTtl = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _now = clock ?? DateTime.now;

  final String apiKey;
  final AppDatabase _db;
  final http.Client _http;
  final List<OfficialChannel> channels;

  /// Каналы только для трейлеров.
  final List<OfficialChannel> trailerChannels;

  /// Страна пользователя (ISO 3166-1): ролики, недоступные в регионе,
  /// не попадают в выдачу.
  final String? regionCode;
  final Duration ttl;
  final Duration emptyTtl;
  final DateTime Function() _now;

  /// Каналы, которые выкладывают аниме бесплатно и официально.
  static const defaultChannels = YouTubeMatch.officialChannels;

  static final _api = Uri.parse('https://www.googleapis.com/youtube/v3/');

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<List<EmbeddedVideo>> find(
    AnimeDetails title, {
    bool refresh = false,
  }) async {
    if (!isConfigured) return const [];
    final result = <EmbeddedVideo>[];
    for (final channel in channels) {
      try {
        result.addAll(await _search(channel, title, refresh: refresh));
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

  @override
  Future<EmbeddedVideo?> findTrailer(
    AnimeDetails title, {
    bool refresh = false,
  }) async {
    if (!isConfigured) return null;
    for (final channel in trailerChannels) {
      try {
        final found = await _search(
          channel,
          title,
          refresh: refresh,
          trailer: true,
        );
        if (found.isNotEmpty) return found.first;
      } on Object {
        // Как и у серий: ошибка канала — пробуем следующий.
      }
    }
    return null;
  }

  Future<List<EmbeddedVideo>> _search(
    OfficialChannel channel,
    AnimeDetails title, {
    required bool refresh,
    bool trailer = false,
  }) async {
    List<EmbeddedVideo> parse(List<Map<String, dynamic>> items) => [
      for (final item in items)
        ?(trailer
            ? parseTrailerItem(item, channel.name, title)
            : parseSearchItem(item, channel.name, title)),
    ];
    final key =
        'yt:${trailer ? 'trailer:' : ''}${channel.handle}:${title.id}:'
        '${regionCode ?? ''}';
    final cached = refresh ? null : await _db.entry(key);
    if (cached != null) {
      final videos = parse(
        (jsonDecode(cached.payload) as List).cast<Map<String, dynamic>>(),
      );
      final age = _now().difference(cached.updatedAt);
      if (age < (videos.isEmpty ? emptyTtl : ttl)) return videos;
    }
    final channelId = await _channelId(channel);
    if (channelId == null) return const [];
    final json = await _get('search', {
      'part': 'snippet',
      'type': 'video',
      'videoEmbeddable': 'true',
      'channelId': channelId,
      'q': trailer
          ? '${title.anime.title.romaji ?? title.anime.title.preferred} '
                'trailer|PV|teaser'
          : title.anime.title.romaji ?? title.anime.title.preferred,
      'maxResults': trailer ? '25' : '50',
      'regionCode': ?regionCode,
    });
    final items = (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    await _db.putEntry(key, jsonEncode(items), _now());
    return parse(items);
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
    final videoTitle = YouTubeMatch.unescape(
      snippet?['title'] as String? ?? '',
    );
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

  /// Трейлер из ответа `search.list` (см. [YouTubeMatch.isTrailerFor]).
  static EmbeddedVideo? parseTrailerItem(
    Map<String, dynamic> item,
    String channel,
    AnimeDetails title,
  ) {
    final videoId = (item['id'] as Map?)?['videoId'] as String?;
    final snippet = item['snippet'] as Map?;
    final videoTitle = YouTubeMatch.unescape(
      snippet?['title'] as String? ?? '',
    );
    if (videoId == null || !YouTubeMatch.isTrailerFor(videoTitle, title)) {
      return null;
    }
    final thumbs = snippet?['thumbnails'] as Map?;
    return EmbeddedVideo(
      sourceId: 'youtube',
      videoId: videoId,
      title: videoTitle,
      channel: channel,
      isTrailer: true,
      thumbnail:
          ((thumbs?['medium'] ?? thumbs?['default']) as Map?)?['url']
              as String?,
    );
  }

  static bool matchesTitle(String videoTitle, AnimeDetails title) =>
      YouTubeMatch.matchesTitle(videoTitle, title);

  static int? episodeNumber(String videoTitle) =>
      YouTubeMatch.episodeNumber(videoTitle);
}
