import '../models/anime.dart';

/// Видео, которое воспроизводится только официальным встраиваемым плеером
/// площадки (iframe/WebView). Прямых ссылок на видеопоток в модели нет:
/// приложение не скачивает и не проигрывает потоки сторонних сайтов.
class EmbeddedVideo {
  const EmbeddedVideo({
    required this.sourceId,
    required this.videoId,
    required this.title,
    required this.channel,
    this.episode,
    this.thumbnail,
    this.isTrailer = false,
  });

  /// Id источника ([VideoSource.id]).
  final String sourceId;

  /// Id ролика на площадке.
  final String videoId;
  final String title;

  /// Канал правообладателя.
  final String channel;

  /// Номер серии, если удалось определить по названию.
  final int? episode;
  final String? thumbnail;

  /// Трейлер (PV, тизер), а не серия.
  final bool isTrailer;

  /// Страница официального встраиваемого плеера.
  Uri get embedUrl =>
      Uri.parse('https://www.youtube.com/embed/$videoId?playsinline=1&rel=0');

  /// Страница ролика на площадке.
  Uri get watchUrl => Uri.parse('https://www.youtube.com/watch?v=$videoId');
}

/// Источник видео (этап 6). Источники ищут легальные официальные видео
/// для тайтла и отдают только [EmbeddedVideo].
abstract interface class VideoSource {
  String get id;

  /// Название для интерфейса, например «YouTube».
  String get name;

  /// Источник настроен (есть ключ API и т.п.). Ненастроенный источник
  /// ничего не ищет и в сеть не обращается.
  bool get isConfigured;

  /// Видео тайтла, по возрастанию номера серии. Без сети или при ошибке
  /// API — пустой список, а не исключение. [refresh] — не брать из кэша
  /// («Проверить снова»).
  Future<List<EmbeddedVideo>> find(AnimeDetails title, {bool refresh = false});

  /// Официальный трейлер тайтла или `null` — тоже без исключений.
  Future<EmbeddedVideo?> findTrailer(
    AnimeDetails title, {
    bool refresh = false,
  });
}

/// Подключённые источники видео.
class VideoSources {
  const VideoSources(this.sources);

  final List<VideoSource> sources;

  /// Есть ли хотя бы один настроенный источник.
  bool get anyConfigured => sources.any((s) => s.isConfigured);

  /// Видео из первого настроенного источника, который что-то нашёл.
  Future<List<EmbeddedVideo>> find(
    AnimeDetails title, {
    bool refresh = false,
  }) async {
    for (final s in sources) {
      if (!s.isConfigured) continue;
      final found = await s.find(title, refresh: refresh);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  /// Трейлер из первого настроенного источника, который его нашёл.
  Future<EmbeddedVideo?> findTrailer(
    AnimeDetails title, {
    bool refresh = false,
  }) async {
    for (final s in sources) {
      if (!s.isConfigured) continue;
      if (await s.findTrailer(title, refresh: refresh) case final v?) {
        return v;
      }
    }
    return null;
  }
}
