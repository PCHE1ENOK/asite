// Скриншоты экранов для визуальной проверки:
// flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
// PNG пишутся в test/screenshots/out/ (не в git).
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anime_viewer/data/settings/app_preferences.dart';

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

  Future<void> shot(WidgetTester tester, String name) async {
    await _precacheAll(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/$name.png'),
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
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    await shot(tester, '03-title-stats-dark');
    await tester.tap(find.text('Описание'));
    await tester.pumpAndSettle();
    await shot(tester, '04-title-description-dark');
    await tester.tap(find.text('Похожие'));
    await tester.pumpAndSettle();
    await shot(tester, '05-title-similar-dark');

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
    await h.dispose(tester);
  }, skip: !enabled);
}
