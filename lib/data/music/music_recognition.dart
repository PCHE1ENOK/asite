import '../sources/audio_snippet.dart';

/// Найденная запись (данные MusicBrainz из ответа AcoustID).
class MusicMatch {
  const MusicMatch({
    required this.recordingId,
    required this.title,
    required this.artists,
    this.releaseGroupId,
    this.score,
  });

  /// MBID записи MusicBrainz.
  final String recordingId;
  final String title;
  final List<String> artists;

  /// MBID группы релизов — для обложки из Cover Art Archive.
  final String? releaseGroupId;

  /// Уверенность AcoustID, 0–1.
  final double? score;

  String get artist => artists.join(', ');

  /// «Исполнитель — Название» для копирования.
  String get display => artists.isEmpty ? title : '$artist — $title';

  Uri get musicBrainzUrl =>
      Uri.parse('https://musicbrainz.org/recording/$recordingId');

  /// Обложка, если она есть в Cover Art Archive (иначе ответ 404).
  Uri? get coverArtUrl => releaseGroupId == null
      ? null
      : Uri.parse(
          'https://coverartarchive.org/release-group/$releaseGroupId/front-250',
        );
}

/// Итог распознавания; соответствует состояниям `MusicPanel` в дизайне.
sealed class MusicRecognitionResult {
  const MusicRecognitionResult();
}

/// Пользователь не включил «Распознавать музыку».
class RecognitionDisabled extends MusicRecognitionResult {
  const RecognitionDisabled();
}

/// Распознавание недоступно в этой сборке (нет ключа AcoustID или ещё
/// не подключены источник звука и Chromaprint).
class RecognitionUnavailable extends MusicRecognitionResult {
  const RecognitionUnavailable(this.reason);

  final String reason;
}

class MusicFound extends MusicRecognitionResult {
  const MusicFound(this.matches);

  /// Совпадения по убыванию уверенности.
  final List<MusicMatch> matches;
}

class MusicNotFound extends MusicRecognitionResult {
  const MusicNotFound();
}

/// Нет связи с AcoustID и т.п.
class RecognitionFailed extends MusicRecognitionResult {
  const RecognitionFailed(this.message);

  final String message;
}

/// Отпечаток Chromaprint.
class AudioFingerprint {
  const AudioFingerprint({required this.fingerprint, required this.duration});

  /// Сжатый отпечаток в base64, как его принимает AcoustID.
  final String fingerprint;
  final Duration duration;
}

/// Считает отпечаток Chromaprint на устройстве (этап 4.5).
abstract interface class AudioFingerprinter {
  Future<AudioFingerprint> fingerprint(AudioSnippet snippet);
}

/// Распознаёт музыку в серии на позиции воспроизведения.
abstract interface class MusicRecognizer {
  Future<MusicRecognitionResult> recognize(
    EpisodeRef episode,
    Duration position,
  );
}

/// Заглушка до этапа 4.5: всегда «недоступно».
class StubMusicRecognizer implements MusicRecognizer {
  const StubMusicRecognizer();

  @override
  Future<MusicRecognitionResult> recognize(
    EpisodeRef episode,
    Duration position,
  ) async => const RecognitionUnavailable(
    'Распознавание музыки появится вместе с плеером',
  );
}

/// Проверки перед распознаванием: настройка пользователя и ключ AcoustID.
/// Без согласия пользователя фрагмент звука никуда не отправляется.
class MusicRecognitionGate implements MusicRecognizer {
  const MusicRecognitionGate({
    required this.isEnabled,
    required this.hasApiKey,
    required this.recognizer,
  });

  /// Настройка «Распознавать музыку» (по умолчанию выключена).
  final Future<bool> Function() isEnabled;
  final bool hasApiKey;
  final MusicRecognizer recognizer;

  @override
  Future<MusicRecognitionResult> recognize(
    EpisodeRef episode,
    Duration position,
  ) async {
    if (!await isEnabled()) return const RecognitionDisabled();
    if (!hasApiKey) {
      return const RecognitionUnavailable('Не задан ключ AcoustID');
    }
    return recognizer.recognize(episode, position);
  }
}
