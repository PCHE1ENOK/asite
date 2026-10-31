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
      find.textContaining('Нет ключа YouTube — официальные видео не ищутся'),
      findsOneWidget,
    );
    expect(find.byTooltip('Смотреть на YouTube'), findsNothing);

    await tester.tap(find.text('Начать просмотр'));
    await tester.pumpAndSettle();
    expect(find.byType(NoSourcesScreen), findsOneWidget);
    expect(find.text('Нет ключа YouTube'), findsOneWidget);
    expect(find.text('Проверить снова'), findsNothing);

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
      find.textContaining('Нет ключа YouTube — официальные видео не ищутся'),
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

  testWidgets('key set, nothing found: says so and checks again', (
    tester,
  ) async {
    h.videoSource.isConfigured = true;
    await openAot(tester);
    expect(
      find.textContaining(
        'Официального бесплатного видео для этого тайтла не нашлось '
        '(в вашем регионе)',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Нет ключа YouTube'), findsNothing);
    expect(h.videoSource.findCalls, [false]);

    // «Проверить снова» в карточке — поиск без кэша.
    h.videoSource.videos = const [
      EmbeddedVideo(
        sourceId: 'fake',
        videoId: 'abc',
        title: 'Attack on Titan Episode 1',
        channel: 'Muse Asia',
        episode: 1,
      ),
    ];
    await tester.tap(find.text('Проверить снова'));
    await UiHarness.settle(tester);
    expect(h.videoSource.findCalls, [false, true]);
    expect(find.text('Начать просмотр на YouTube'), findsOneWidget);
    expect(find.textContaining('не нашлось'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('player without video: check again from the player', (
    tester,
  ) async {
    h.videoSource.isConfigured = true;
    await openAot(tester);
    await tester.tap(find.text('Начать просмотр'));
    await tester.pumpAndSettle();
    expect(
      find.text('Официального бесплатного видео не нашлось'),
      findsOneWidget,
    );
    await tester.tap(find.text('Проверить снова'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NoSourcesScreen), findsNothing);
    expect(h.videoSource.findCalls, [false, true]);
    await h.dispose(tester);
  });

  testWidgets('trailer button: shown only when a trailer exists', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    h.videoSource.isConfigured = true;
    await openAot(tester);
    expect(find.text('Трейлер на YouTube'), findsNothing);
    expect(h.videoSource.trailerCalls, [false], reason: 'no search on open');

    // Поиск — только по нажатию «Найти трейлер».
    await tester.tap(find.text('Найти трейлер'));
    await UiHarness.settle(tester);
    expect(h.videoSource.trailerCalls, [false, true]);
    expect(find.text('Трейлер на YouTube'), findsNothing);
    expect(find.text('Найти трейлер'), findsNothing, reason: 'searched once');
    expect(find.textContaining('рейлер'), findsNothing, reason: 'no error');
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('search on tap finds a trailer', (tester) async {
    h.videoSource
      ..isConfigured = true
      ..searchedTrailer = const EmbeddedVideo(
        sourceId: 'fake',
        videoId: 'srch',
        title: 'Attack on Titan | Official Trailer',
        channel: 'Crunchyroll',
        isTrailer: true,
      );
    await openAot(tester);
    await tester.tap(find.text('Найти трейлер'));
    await UiHarness.settle(tester);
    expect(find.text('Трейлер на YouTube'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('no key: no trailer buttons at all', (tester) async {
    await openAot(tester);
    expect(find.text('Найти трейлер'), findsNothing);
    expect(find.text('Трейлер на YouTube'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('trailer opens in the embedded YouTube player', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    const trailer = EmbeddedVideo(
      sourceId: 'fake',
      videoId: 'trl',
      title: 'Attack on Titan | Official Trailer',
      channel: 'Crunchyroll',
      isTrailer: true,
    );
    h.videoSource
      ..isConfigured = true
      ..trailer = trailer;
    await openAot(tester);
    expect(find.text('Трейлер на YouTube'), findsOneWidget);
    await tester.tap(find.text('Трейлер на YouTube'));
    await UiHarness.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final player = tester.widget<YouTubePlayerScreen>(
      find.byType(YouTubePlayerScreen),
    );
    expect(player.video.videoId, 'trl');
    expect(player.video.embedUrl.host, 'www.youtube.com');
    expect(player.video.embedUrl.path, '/embed/trl');
    expect(find.textContaining('Трейлер · Crunchyroll'), findsOneWidget);
    expect(find.textContaining('просмотренной'), findsNothing);
    await tester.pageBack();
    await UiHarness.settle(tester);
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
