import 'dart:async';
import 'dart:convert';

import 'package:anime_viewer/data/translation/translation.dart';
import 'package:anime_viewer/ui/title/comments_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'comments_ui_test.dart' show thread, video;
import 'ui_harness.dart';

const en = 'Rewatching in 2026 and it still hits different';
const ja = 'オープニングが最高すぎて毎回飛ばせない';

/// Перевод на устройстве: пакет нужен, пока не скачан ([download]).
class _DeviceEngine implements TranslationEngine {
  final download = Completer<bool>();
  bool installed = false;

  @override
  String? get server => null;

  @override
  Future<bool> needsPack(String? source) async => !installed;

  @override
  Future<bool> downloadPack(String? source) async =>
      installed = await download.future;

  @override
  Future<TranslationResult> translate(String text, {String? source}) async =>
      Translated('На устройстве: $text');

  @override
  Future<void> close() async {}
}

void main() {
  late UiHarness h;
  setUp(() {
    h = UiHarness();
    h.videoSource
      ..isConfigured = true
      ..videos = const [video];
    h.commentsHandler = (_) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'items': [
            thread('ru', 'Первая серия до сих пор держит в напряжении'),
            thread('en', en),
            thread('ja', ja),
          ],
        }),
      ),
      200,
    );
  });

  Future<void> openComments(WidgetTester tester) async {
    await h.pump(tester);
    await tester.tap(find.text('Attack on Titan').first);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Комментарии'));
    await tester.tap(find.text('Комментарии'));
    await UiHarness.settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  final translateButtons = find.text('Перевести на русский');

  testWidgets('PC: button only for non-russian, banner, original, cache', (
    tester,
  ) async {
    await openComments(tester);
    expect(translateButtons, findsNWidgets(2));
    expect(find.text('яп.'), findsOneWidget, reason: 'language tag');
    expect(find.text(CommentsTab.attribution), findsOneWidget);

    // Плашка MyMemory над списком; «Не переводить» — без запроса.
    await tap(tester, translateButtons.first);
    expect(
      find.text(
        'Текст комментария отправляется на сервер MyMemory для перевода',
      ),
      findsOneWidget,
    );
    await tap(tester, find.text('Не переводить'));
    expect(find.text('Понятно'), findsNothing);
    expect(h.translateRequests, isEmpty);
    expect(translateButtons, findsNWidgets(2));

    // «Понятно» запускает перевод.
    await tap(tester, translateButtons.last);
    await tap(tester, find.text('Понятно'));
    expect(find.text('Перевод: $ja'), findsOneWidget);
    expect(find.text('Перевод с японского · MyMemory'), findsOneWidget);
    expect(find.text(ja), findsNothing, reason: 'original hidden');
    expect(h.translateRequests.single.queryParameters['langpair'], 'ja|ru');

    await tap(tester, find.text('Показать оригинал'));
    expect(
      tester.getTopLeft(find.text(ja)).dy,
      lessThan(tester.getTopLeft(find.text('Перевод: $ja')).dy),
    );
    await tap(tester, find.text('Скрыть оригинал'));
    expect(find.text(ja), findsNothing);

    // Второй раз плашки нет; язык неизвестен — Autodetect.
    await tap(tester, translateButtons);
    expect(find.text('Понятно'), findsNothing);
    expect(find.text('Перевод: $en'), findsOneWidget);
    expect(find.text('Перевод · MyMemory'), findsOneWidget);
    expect(
      h.translateRequests.last.queryParameters['langpair'],
      'Autodetect|ru',
    );

    // Кэш на сессию: после смены вкладки — без новых запросов.
    await tap(tester, find.text('Описание'));
    await tap(tester, find.text('Комментарии'));
    expect(find.text('Перевод: $ja'), findsOneWidget);
    expect(h.translateRequests, hasLength(2));
    await h.dispose(tester);
  });

  testWidgets('PC: quota exceeded', (tester) async {
    await tester.runAsync(
      () => h.services.preferences.setMyMemoryConsent(true),
    );
    h.translateHandler = (_) => http.Response.bytes(
      utf8.encode(jsonEncode({'quotaFinished': true, 'responseStatus': 429})),
      200,
    );
    await openComments(tester);
    await tap(tester, translateButtons.first);
    expect(
      find.text('Лимит перевода исчерпан, попробуйте завтра'),
      findsOneWidget,
    );
    expect(translateButtons, findsOneWidget, reason: 'no retry for this one');
    await h.dispose(tester);
  });

  testWidgets('network error: message and retry, no crash', (tester) async {
    await tester.runAsync(
      () => h.services.preferences.setMyMemoryConsent(true),
    );
    h.translateHandler = (_) => throw http.ClientException('offline');
    await openComments(tester);
    await tap(tester, translateButtons.first);
    expect(tester.takeException(), isNull);
    expect(find.text('Не удалось перевести: нет сети'), findsOneWidget);

    h.translateHandler = (uri) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'responseStatus': 200,
          'responseData': {'translatedText': 'Снова в 2026'},
        }),
      ),
      200,
    );
    await tap(tester, find.text('Повторить'));
    expect(find.text('Снова в 2026'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('phone: language pack, progress, done on device', (tester) async {
    final engine = _DeviceEngine();
    h.translationEngine = engine;
    await openComments(tester);
    expect(
      find.text(
        '${CommentsTab.attribution} · перевод выполняется на устройстве',
      ),
      findsOneWidget,
    );
    await tap(tester, translateButtons.last);
    expect(find.text('Понятно'), findsNothing, reason: 'no banner on device');
    expect(
      find.textContaining('Для перевода с японского нужен языковой пакет'),
      findsOneWidget,
    );
    await tester.tap(find.text('Скачать пакет перевода'));
    await tester.pump();
    expect(find.text('Скачиваем пакет «яп. → рус.»'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    engine.download.complete(true);
    await UiHarness.settle(tester);
    expect(find.text('На устройстве: $ja'), findsOneWidget);
    expect(find.text('Перевод с японского · на устройстве'), findsOneWidget);
    await h.dispose(tester);
  });
}
