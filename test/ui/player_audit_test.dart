import 'dart:convert';

import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:anime_viewer/ui/player/windows_youtube_player.dart';
import 'package:anime_viewer/ui/player/youtube_player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'ui_harness.dart';

/// Подменённый url_launcher: запоминает ссылки, может «не открыть».
class FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  bool succeed = true;
  final launched = <(String, PreferredLaunchMode)>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return succeed;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}

const video = EmbeddedVideo(
  sourceId: 'fake',
  videoId: 'abc123XYZ_-',
  title: 'Attack on Titan Episode 1',
  channel: 'Muse Asia',
  episode: 1,
);

void main() {
  late UiHarness h;
  late FakeLauncher launcher;

  setUp(() {
    h = UiHarness();
    launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    h.videoSource
      ..isConfigured = true
      ..videos = const [video];
  });

  /// Открывает плеер YouTube из карточки тайтла (Windows без WebView2 в
  /// тестах — экран перехода на youtube.com).
  Future<void> openPlayer(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать просмотр на YouTube'));
    await UiHarness.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(YouTubePlayerScreen), findsOneWidget);
  }

  Future<void> done(WidgetTester tester) async {
    await h.dispose(tester);
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('«Открыть на YouTube» opens the watch page externally', (
    tester,
  ) async {
    await openPlayer(tester);
    await tester.tap(find.byTooltip('Открыть на YouTube'));
    await tester.pump();
    expect(launcher.launched.single.$1, video.watchUrl.toString());
    expect(
      launcher.launched.single.$2,
      PreferredLaunchMode.externalApplication,
    );
    await done(tester);
  });

  testWidgets('failed browser launch is reported, not silently ignored', (
    tester,
  ) async {
    launcher.succeed = false;
    await openPlayer(tester);
    await tester.tap(find.byTooltip('Открыть на YouTube'));
    await tester.pump();
    expect(find.text('Не удалось открыть YouTube'), findsOneWidget);

    await tester.tap(find.text('Открыть на YouTube'));
    await tester.pump();
    expect(launcher.launched, hasLength(2));
    await done(tester);
  });

  testWidgets('mark watched in the YouTube player', (tester) async {
    await openPlayer(tester);
    await tester.tap(find.text('Отметить серию 1 просмотренной'));
    await UiHarness.settle(tester);
    expect(find.text('Серия 1 просмотрена'), findsOneWidget);
    final e = await UiHarness.run(
      tester,
      () => h.services.library.entry(16498),
    );
    expect(e?.status, ListStatus.current);
    await done(tester);
  });

  testWidgets('our controls sit above and below the player, never over it', (
    tester,
  ) async {
    await openPlayer(tester);
    final player = tester.getRect(find.byType(WindowsYouTubePlayer));
    final bar = tester.getRect(find.byType(AppBar));
    final mark = tester.getRect(find.text('Отметить серию 1 просмотренной'));
    expect(bar.bottom, lessThanOrEqualTo(player.top));
    expect(mark.top, greaterThanOrEqualTo(player.bottom));
    await done(tester);
  });

  testWidgets('fullscreen: button, F and Esc', (tester) async {
    await openPlayer(tester);
    expect(find.byType(AppBar), findsOneWidget);

    await tester.tap(find.byTooltip('Полный экран'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Отметить серию 1 просмотренной'), findsNothing);
    expect(find.byType(WindowsYouTubePlayer), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);

    // F по физической клавише (на русской раскладке — «а»).
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyA,
      physicalKey: PhysicalKeyboardKey.keyF,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    await tester.sendKeyEvent(
      LogicalKeyboardKey.keyA,
      physicalKey: PhysicalKeyboardKey.keyF,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    await done(tester);
  });

  testWidgets('YouTube button on an episode row opens that episode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Смотреть на YouTube'));
    await UiHarness.settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(YouTubePlayerScreen), findsOneWidget);
    expect(find.textContaining('Серия 1 · Официальное видео'), findsOneWidget);
    await done(tester);
  });

  testWidgets('comments panel opens under the video, not over it', (
    tester,
  ) async {
    h.commentsHandler = (_) => http.Response.bytes(
      utf8.encode(
        '{"items":[{"snippet":{"topLevelComment":{"id":"c1","snippet":'
        '{"authorDisplayName":"Mika","textOriginal":"Отличная серия",'
        '"likeCount":3,"publishedAt":"2026-10-01T12:00:00Z"}}}}]}',
      ),
      200,
    );
    await openPlayer(tester);
    await tester.tap(find.text('Комментарии'));
    await UiHarness.settle(tester);

    expect(find.text('Отличная серия'), findsOneWidget);
    expect(find.text('Комментарии — с YouTube'), findsOneWidget);
    final player = tester.getRect(find.byType(WindowsYouTubePlayer));
    final comment = tester.getRect(find.text('Отличная серия'));
    expect(comment.top, greaterThanOrEqualTo(player.bottom));

    // Повторное нажатие закрывает панель.
    await tester.tap(find.text('Комментарии').first);
    await UiHarness.settle(tester);
    expect(find.text('Отличная серия'), findsNothing);
    await done(tester);
  });
}
