// Скриншоты экранов для отчёта и визуальной проверки (golden-рендер в
// headless-режиме, не запуск на устройстве):
// flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
// PNG пишутся в golden/ в корне репозитория.
@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:anime_viewer/data/models/library_entry.dart';
import 'package:anime_viewer/data/models/title_note.dart';
import 'package:anime_viewer/data/settings/app_preferences.dart';
import 'package:anime_viewer/data/sources/video_source.dart';

import 'package:anime_viewer/ui/profiles/profile_widgets.dart';

import '../ui/ui_harness.dart';

const enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final symbols = Directory('$pubCache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('material_symbols_icons-'));
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';

  await load('Golos Text', [
    'assets/fonts/GolosText-Regular.ttf',
    'assets/fonts/GolosText-Medium.ttf',
    'assets/fonts/GolosText-SemiBold.ttf',
  ]);
  await load('Unbounded', ['assets/fonts/Unbounded-SemiBold.ttf']);
  await load('packages/material_symbols_icons/MaterialSymbolsRounded', [
    '${symbols.path}/lib/fonts/MaterialSymbolsRounded.ttf',
  ]);
  await load('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Градиентные «обложки» вместо сетевых картинок.
final _images = <String, MemoryImage>{};

Future<MemoryImage> _render(String url) async {
  final hash = url.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0xFFFFFF);
  final hue = (hash % 360).toDouble();
  final banner = url.contains('banner');
  final w = banner ? 1200.0 : 230.0, h = banner ? 300.0 : 345.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final a = HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
  final b = HSLColor.fromAHSL(1, (hue + 50) % 360, 0.6, 0.22).toColor();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(w * 0.4, h), [a, b]),
  );
  canvas.drawCircle(
    Offset(w * 0.7, h * 0.3),
    w * 0.35,
    Paint()..color = Colors.white.withValues(alpha: 0.12),
  );
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(png!.buffer.asUint8List());
}

Future<void> prerender(WidgetTester tester, List<String> urls) => tester
    .runAsync(() async {
      for (final u in urls) {
        _images[u] ??= await _render(u);
      }
    })
    .then((_) {});

ImageProvider resolve(String url) =>
    _images[url] ?? MemoryImage(transparentPng);

Future<void> _precacheAll(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in tester.allElements.toList()) {
      if (e.widget is Image) {
        await precacheImage((e.widget as Image).image, e);
      }
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final urls = [
    for (var i = 0; i < 30; i++) ...[
      'https://img.test/cover/${1000 + i}.jpg',
      'https://img.test/cover/${1000 + i}-s.jpg',
      'https://img.test/banner/${1000 + i}.jpg',
    ],
    'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498.jpg',
    'https://s4.anilist.co/file/anilistcdn/media/anime/banner/16498-8jpFCOcDmneX.jpg',
  ];

  Future<UiHarness> start(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.runAsync(loadFonts);
    await prerender(tester, urls);
    final h = UiHarness(images: resolve);
    await tester.runAsync(() async {
      final lib = h.services.library;
      await lib.setStatus(1000, ListStatus.current);
      await lib.setProgress(1000, 12);
      await lib.setStatus(1001, ListStatus.current);
      await lib.markWatched(1001, 5, totalEpisodes: 25);
      await lib.setStatus(1003, ListStatus.completed);
      await lib.setStatus(1005, ListStatus.planning);
      await lib.setStatus(1007, ListStatus.paused);
      await lib.setStatus(1009, ListStatus.dropped);
      await lib.setStatus(1013, ListStatus.planning);
      await h.services.profiles.create('Каито', color: 3);
    });
    await tester.runAsync(
      () => h.services.preferences.setTheme(
        brightness == Brightness.dark
            ? ThemePreference.dark
            : ThemePreference.light,
      ),
    );
    await h.pump(tester, size: size);
    await _precacheAll(tester);
    return h;
  }

  Future<void> shot(
    WidgetTester tester,
    String name, {
    bool precache = true,
  }) async {
    if (precache) await _precacheAll(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../golden/$name.png'),
    );
  }

  Future<void> openTitle(WidgetTester tester) async {
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop dark', (tester) async {
    final h = await start(tester, size: const Size(1440, 900));
    await shot(tester, '01-catalog-dark');

    await openTitle(tester);
    await shot(tester, '02-title-episodes-dark');
    await tester.tap(find.text('Начать просмотр'));
    await tester.pumpAndSettle();
    await shot(tester, '21-player-no-sources-dark');
    await tester.tap(find.text('Вернуться к тайтлу'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    await shot(tester, '03-title-stats-dark');
    await tester.tap(find.text('Описание'));
    await tester.pumpAndSettle();
    await shot(tester, '04-title-description-dark');
    await tester.tap(find.text('Похожие'));
    await tester.pumpAndSettle();
    await shot(tester, '05-title-similar-dark');
    await tester.runAsync(
      () => h.services.notes.save(
        TitleNote(
          mediaId: 16498,
          updatedAt: DateTime.now(),
          summary: 'Сильный старт, затянутая середина',
          verdict: NoteVerdict.recommend,
          liked: 'Музыка и постановка боёв',
          moments: const [
            NoteMoment(
              episode: 1,
              timecode: Duration(minutes: 21, seconds: 40),
              text: 'Стена Мария',
            ),
            NoteMoment(episode: 5, text: 'Неожиданный поворот'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Заметка'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await shot(tester, '22-title-note-dark');

    await tester.tap(find.text('Поиск').first);
    await UiHarness.settle(tester);
    await shot(tester, '06-search-idle-dark');
    await tester.enterText(find.byType(TextField), 'Fri');
    await tester.pump(const Duration(milliseconds: 350));
    await UiHarness.settle(tester);
    await shot(tester, '07-search-results-dark');

    await tester.tap(find.text('Настройки').first);
    await UiHarness.settle(tester);
    await shot(tester, '08-settings-dark');

    await tester.tap(find.byType(ProfileMenuButton));
    await tester.pumpAndSettle();
    await shot(tester, '17-profile-menu-dark');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Списки').first);
    await UiHarness.settle(tester);
    await shot(tester, '14-lists-grid-dark');
    await tester.tap(find.byTooltip('Список'));
    await tester.pumpAndSettle();
    await shot(tester, '15-lists-list-dark');
    await h.dispose(tester);
  }, skip: !enabled);

  testWidgets('desktop light', (tester) async {
    final h = await start(
      tester,
      size: const Size(1280, 800),
      brightness: Brightness.light,
    );
    await shot(tester, '09-catalog-light');
    await openTitle(tester);
    await tester.tap(find.byTooltip('Отметить просмотренной').first);
    await UiHarness.settle(tester);
    await shot(tester, '16-title-episode-marked-light');
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    await shot(tester, '10-title-stats-light');
    await h.dispose(tester);
  }, skip: !enabled);

  testWidgets('catalog states', (tester) async {
    final h = UiHarness(images: resolve)..offline = true;
    await tester.runAsync(loadFonts);
    await h.pump(tester, size: const Size(1280, 800));
    await shot(tester, '11-catalog-error-dark');
    await h.dispose(tester);
  }, skip: !enabled);

  testWidgets('phone', (tester) async {
    final h = await start(tester, size: const Size(390, 844));
    await shot(tester, '12-phone-catalog-dark');
    await openTitle(tester);
    await shot(tester, '13-phone-title-dark');
    await tester.tap(find.text('Профиль'));
    await UiHarness.settle(tester);
    await shot(tester, '18-phone-settings-dark');
    await tester.longPress(find.text('Профиль'));
    await tester.pumpAndSettle();
    await shot(tester, '19-phone-profile-sheet-dark');
    await tester.tap(find.text('Каито').last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await shot(tester, '20-phone-profile-switch-dark', precache: false);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    await h.dispose(tester);
  }, skip: !enabled);

  testWidgets('comments', (tester) async {
    await tester.runAsync(loadFonts);
    await prerender(tester, urls);
    final h = UiHarness(images: resolve);
    h.videoSource
      ..isConfigured = true
      ..videos = const [
        EmbeddedVideo(
          sourceId: 'fake',
          videoId: 'abc123XYZ_-',
          title: 'Attack on Titan Episode 1',
          channel: 'Muse Asia',
          episode: 1,
        ),
        EmbeddedVideo(
          sourceId: 'fake',
          videoId: 'def456XYZ_-',
          title: 'Attack on Titan Episode 2',
          channel: 'Muse Asia',
          episode: 2,
        ),
      ];
    Map<String, dynamic> c(String who, String text, int likes, int replies) => {
      'snippet': {
        'totalReplyCount': replies,
        'topLevelComment': {
          'id': who,
          'snippet': {
            'authorDisplayName': who,
            'textOriginal': text,
            'likeCount': likes,
            'publishedAt': '2026-10-0${replies + 1}T12:00:00Z',
          },
        },
      },
    };
    h.commentsHandler = (_) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'nextPageToken': 'P2',
          'items': [
            c(
              'Mika',
              'Первая серия до сих пор держит в напряжении. Музыка в финале — мурашки.',
              12400,
              3,
            ),
            c('Ren', 'Rewatching in 2026 and it still hits different', 3100, 1),
            c(
              'Аня',
              'Пересматриваю перед финальным сезоном, замечаю детали, которые пропустила.',
              890,
              0,
            ),
          ],
        }),
      ),
      200,
    );
    await tester.runAsync(
      () => h.services.preferences.setTheme(ThemePreference.dark),
    );
    await h.pump(tester, size: const Size(1440, 900));
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Комментарии'));
    await UiHarness.settle(tester);
    await shot(tester, '23-title-comments-dark');
    await h.dispose(tester);
  }, skip: !enabled);
}
