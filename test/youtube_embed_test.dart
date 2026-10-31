import 'package:anime_viewer/ui/player/youtube_embed.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embed kind per platform', () {
    expect(embedKindFor(TargetPlatform.android), EmbedKind.webview);
    expect(embedKindFor(TargetPlatform.iOS), EmbedKind.webview);
    expect(embedKindFor(TargetPlatform.windows), EmbedKind.webview2);
    expect(embedKindFor(TargetPlatform.linux), EmbedKind.browser);
    expect(
      embedKindFor(TargetPlatform.windows, isWeb: true),
      EmbedKind.browser,
    );
  });

  test('player page holds only the official YouTube iframe', () {
    final html = youtubePlayerHtml('dQw4w9WgXcQ');
    final urls = RegExp(r'''(?:src|href)="([^"]+)"''')
        .allMatches(html)
        .map((m) => Uri.parse(m.group(1)!))
        .toList();
    expect(urls, hasLength(2));
    expect(urls.every((u) => u.host == 'www.youtube.com'), isTrue);
    expect(urls.last.path, '/iframe_api', reason: 'only for onReady/onError');
    final src = urls.first;
    expect(src.queryParameters['enablejsapi'], '1');
    expect(src.host, 'www.youtube.com');
    expect(src.path, '/embed/dQw4w9WgXcQ');
    expect(src.queryParameters['origin'], playerOrigin);
    // Полный экран — только наш: кнопка fullscreen iframe в WebView не
    // работает без поддержки со стороны приложения.
    expect(src.queryParameters['fs'], '0');
    expect(html, isNot(contains('<video')));
    expect(html, isNot(matches(RegExp(r'\.(m3u8|mpd|mp4|webm)\b'))));
  });

  test('video id is validated (no injection into the page)', () {
    expect(() => youtubePlayerHtml('a"><script>'), throwsArgumentError);
    expect(() => youtubePlayerHtml(''), throwsArgumentError);
  });

  test('IFrame API messages: ready, error codes, garbage', () {
    expect(PlayerEvent.parse({'event': 'ready'}), isA<PlayerReady>());
    expect(
      (PlayerEvent.parse('{"event":"error","code":153}')! as PlayerError).code,
      '153',
    );
    expect(
      PlayerEvent.parse({'event': 'error', 'code': 150}),
      isA<PlayerError>(),
    );
    expect(PlayerEvent.parse('not json'), isNull);
    expect(PlayerEvent.parse({'event': 'other'}), isNull);
    expect(PlayerEvent.parse(42), isNull);
  });

  test('error reasons', () {
    expect(const PlayerError('153').reason, contains('настройки встраивания'));
    expect(const PlayerError('152').reason, contains('настройки встраивания'));
    expect(const PlayerError('150').reason, contains('запретил'));
    expect(const PlayerError('101').reason, contains('запретил'));
    expect(const PlayerError('100').reason, contains('удалён'));
    expect(const PlayerError('timeout').reason, 'Плеер YouTube не ответил');
    expect(
      const PlayerError('load:connectionAborted').reason,
      contains('не загрузилась'),
    );
    expect(const PlayerError('999').reason, 'Плеер YouTube сообщил об ошибке');
  });

  test('page posts events to both bridges', () {
    final html = youtubePlayerHtml('dQw4w9WgXcQ');
    expect(html, contains('chrome.webview.postMessage'));
    expect(html, contains('window.$playerBridge.postMessage'));
    expect(html, contains('onError'));
    expect(html, contains("code: 'script'"));
  });
}
