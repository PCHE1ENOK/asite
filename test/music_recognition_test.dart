import 'package:anime_viewer/data/music/music_recognition.dart';
import 'package:anime_viewer/data/sources/audio_snippet.dart';
import 'package:flutter_test/flutter_test.dart';

class _Found implements MusicRecognizer {
  var calls = 0;

  @override
  Future<MusicRecognitionResult> recognize(EpisodeRef e, Duration p) async {
    calls++;
    return const MusicFound([
      MusicMatch(
        recordingId: 'rec-1',
        title: 'Song',
        artists: ['A', 'B'],
        releaseGroupId: 'rg-1',
      ),
    ]);
  }
}

void main() {
  const episode = EpisodeRef(mediaId: 1, episode: 2);

  test('gate: disabled setting never calls the recognizer', () async {
    final inner = _Found();
    final gate = MusicRecognitionGate(
      isEnabled: () async => false,
      hasApiKey: true,
      recognizer: inner,
    );
    expect(
      await gate.recognize(episode, Duration.zero),
      isA<RecognitionDisabled>(),
    );
    expect(inner.calls, 0);
  });

  test('gate: no API key → unavailable', () async {
    final inner = _Found();
    final gate = MusicRecognitionGate(
      isEnabled: () async => true,
      hasApiKey: false,
      recognizer: inner,
    );
    expect(
      await gate.recognize(episode, Duration.zero),
      isA<RecognitionUnavailable>(),
    );
    expect(inner.calls, 0);
  });

  test('gate: enabled with key delegates', () async {
    final gate = MusicRecognitionGate(
      isEnabled: () async => true,
      hasApiKey: true,
      recognizer: _Found(),
    );
    final r = await gate.recognize(episode, Duration.zero) as MusicFound;
    final m = r.matches.single;
    expect(m.display, 'A, B — Song');
    expect(
      m.musicBrainzUrl.toString(),
      'https://musicbrainz.org/recording/rec-1',
    );
    expect(
      m.coverArtUrl.toString(),
      'https://coverartarchive.org/release-group/rg-1/front-250',
    );
  });

  test('stub is unavailable until stage 4.5', () async {
    expect(
      await const StubMusicRecognizer().recognize(episode, Duration.zero),
      isA<RecognitionUnavailable>(),
    );
  });
}
