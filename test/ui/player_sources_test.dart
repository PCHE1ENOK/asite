import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:anime_viewer/ui/player/no_sources_screen.dart';
import 'package:anime_viewer/ui/player/windows_youtube_player.dart';
import 'package:anime_viewer/ui/player/youtube_player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

void main() {
  late UiHarness h;
  setUp(() => h = UiHarness());

  Future<void> openAot(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('no sources: banner, player explains, episode can be marked', (
    tester,
  ) async {
    await openAot(tester);
    expect(
      find.textContaining('Источники видео не подключены. Серии'),
      findsOneWidget,
    );
    expect(find.byTooltip('Смотреть на YouTube'), findsNothing);

    await tester.tap(find.text('Начать просмотр'));
    await tester.pumpAndSettle();
    expect(find.byType(NoSourcesScreen), findsOneWidget);
    expect(find.text('Источники видео не подключены'), findsOneWidget);

    await tester.tap(find.text('Отметить серию 1 просмотренной'));
    await UiHarness.settle(tester);
    expect(find.text('Серия 1 просмотрена'), findsOneWidget);
    final e = await UiHarness.run(
      tester,
      () => h.services.library.entry(16498),
    );
    expect(e?.status, ListStatus.current);

    await tester.tap(find.text('Вернуться к тайтлу'));
    await tester.pumpAndSettle();
    expect(find.text('Смотреть серию 2'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('official video found: watch on YouTube', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    h.videoSource
      ..isConfigured = true
      ..videos = const [
        EmbeddedVideo(
          sourceId: 'fake',
          videoId: 'abc',
          title: 'Attack on Titan Episode 1',
          channel: 'Muse Asia',
          episode: 1,
        ),
      ];
    await openAot(tester);

    expect(
      find.textContaining('Источники видео не подключены. Серии'),
      findsNothing,
    );
    expect(find.byTooltip('Смотреть на YouTube'), findsOneWidget);
    expect(find.text('Начать просмотр на YouTube'), findsOneWidget);

    await tester.tap(find.text('Начать просмотр на YouTube'));
    await UiHarness.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(YouTubePlayerScreen), findsOneWidget);
    expect(
      find.textContaining('Официальное видео · Muse Asia'),
      findsOneWidget,
    );
    // WebView2 в тестах недоступен — переход в официальный плеер на
    // youtube.com.
    expect(find.byType(WindowsYouTubePlayer), findsOneWidget);
    expect(find.text('Смотреть на YouTube'), findsOneWidget);

    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
