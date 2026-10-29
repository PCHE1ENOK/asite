import 'dart:typed_data';

/// Серия, из которой берётся звук.
class EpisodeRef {
  const EpisodeRef({required this.mediaId, required this.episode});

  /// Id тайтла на AniList.
  final int mediaId;
  final int episode;
}

/// Фрагмент звука: PCM 16 бит со знаком, каналы чередуются.
class AudioSnippet {
  const AudioSnippet({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  final Int16List samples;
  final int sampleRate;
  final int channels;

  Duration get duration => Duration(
    microseconds: samples.length * 1000000 ~/ (sampleRate * channels),
  );
}

/// Часть слоя источников видео (этап 6): отдаёт короткий фрагмент звука
/// текущей серии для распознавания музыки. Источник знает, откуда и как
/// идёт поток (дорожка или отдельный поток озвучки), плеер — нет.
abstract interface class AudioSnippetSource {
  /// Фрагмент длиной [length] (8–10 с), начиная с [position].
  Future<AudioSnippet> snippet(
    EpisodeRef episode,
    Duration position, {
    Duration length = const Duration(seconds: 10),
  });
}
