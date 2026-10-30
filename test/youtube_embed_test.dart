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
    expect(urls, hasLength(1));
    final src = urls.single;
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
}
