import 'dart:convert';

import 'package:anime_viewer/data/models/anime.dart';
import 'package:anime_viewer/data/sources/video_source.dart';
import 'package:anime_viewer/ui/player/youtube_embed.dart';
import 'package:anime_viewer/ui/player/youtube_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../fixtures.dart';
import 'player_audit_test.dart' show FakeLauncher;
import 'ui_harness.dart';

const trailer = EmbeddedVideo(
  sourceId: 'fake',
  videoId: 'trlTRL123',
  title: 'Attack on Titan | Official Trailer',
  channel: 'Crunchyroll',
  isTrailer: true,
);

void main() {
  late UiHarness h;
  late FakeLauncher launcher;
  late AnimeDetails details;
  setUp(() {
    h = UiHarness();
    launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    details = AnimeDetails.fromJson(
      (jsonDecode(fixture('details_response.json')) as Map)['data']['Media']
          as Map<String, dynamic>,
    );
  });

  /// Плеер с подменённым iframe: тест сам присылает события IFrame API.
  Future<ValueChanged<PlayerEvent>> openPlayer(WidgetTester tester) async {
    late ValueChanged<PlayerEvent> send;
    var builds = 0;
    await h.pump(tester);
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => YouTubePlayerScreen(
              video: trailer,
              details: details,
              embedBuilder: (id, onEvent) {
                builds++;
                send = onEvent;
                return Text('iframe $id #$builds');
              },
            ),
          ),
        );
    await tester.pumpAndSettle();
    return (e) => send(e);
  }

  testWidgets('error 153: state, code, open in browser, retry', (tester) async {
    final send = await openPlayer(tester);
    expect(find.text('iframe trlTRL123 #1'), findsOneWidget);

    send(const PlayerError('153'));
    await tester.pump();
    expect(find.text('Трейлер не открывается'), findsOneWidget);
    expect(find.text('Код ошибки YouTube: 153'), findsOneWidget);
    expect(find.textContaining('настройки встраивания'), findsOneWidget);
    expect(find.textContaining('iframe'), findsNothing);

    await tester.tap(find.text('Открыть на YouTube').last);
    await tester.pump();
    expect(launcher.launched.single.$1, trailer.watchUrl.toString());

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.textContaining('iframe trlTRL123'), findsOneWidget);
    send(const PlayerReady());
    await tester.pump(playerReadyTimeout * 2);
    expect(find.text('Трейлер не открывается'), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('no onReady in time: «Плеер YouTube не ответил»', (tester) async {
    await openPlayer(tester);
    await tester.pump(playerReadyTimeout - const Duration(seconds: 1));
    expect(find.text('Трейлер не открывается'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Трейлер не открывается'), findsOneWidget);
    expect(find.text('Плеер YouTube не ответил'), findsOneWidget);
    expect(find.text('Код ошибки YouTube: timeout'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('owner forbids embedding (150)', (tester) async {
    final send = await openPlayer(tester);
    send(const PlayerError('150'));
    await tester.pump();
    expect(
      find.text('Владелец запретил показ ролика в приложениях'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });
}
