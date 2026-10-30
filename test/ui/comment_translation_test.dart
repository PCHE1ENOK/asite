import 'dart:async';
import 'dart:convert';

import 'package:anime_viewer/data/translation/translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'comments_ui_test.dart' show thread, video;
import 'ui_harness.dart';

/// Перевод на устройстве: скачивание пакета ждёт [download].
class _DeviceEngine implements TranslationEngine {
  final download = Completer<void>();

  @override
  String? get server => null;

  @override
  Future<TranslationResult> translate(
    String text, {
    String? source,
    void Function(TranslationStage stage)? onStage,
  }) async {
    onStage?.call(TranslationStage.downloadingModel);
    await download.future;
    onStage?.call(TranslationStage.translating);
    return Translated('На устройстве: $text');
  }

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
            thread('en', 'Rewatching in 2026 and it still hits different'),
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

  Future<void> tapTranslate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Перевести на русский'));
    await tester.tap(find.text('Перевести на русский'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> accept(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Перевести'));
    await UiHarness.settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('button only for non-russian; consent; original toggle; cache', (
    tester,
  ) async {
    await openComments(tester);
    expect(find.text('Перевести на русский'), findsOneWidget);

    // ПК: сначала пометка, что текст уходит на сервер MyMemory.
    await tapTranslate(tester);
    expect(find.text('Перевод через MyMemory'), findsOneWidget);
    expect(
      find.textContaining('отправляется на сервер MyMemory'),
      findsOneWidget,
    );
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(h.translateRequests, isEmpty);

    await tapTranslate(tester);
    await accept(tester);
    const translated =
        'Перевод: Rewatching in 2026 and it still hits different';
    expect(find.text(translated), findsOneWidget);
    expect(find.text('Перевод на русский · MyMemory'), findsOneWidget);
    expect(
      find.text('Rewatching in 2026 and it still hits different'),
      findsNothing,
    );
    expect(
      h.translateRequests.single.queryParameters['langpair'],
      'Autodetect|ru',
    );

    // «Показать оригинал»: оригинал над переводом.
    await tester.tap(find.text('Показать оригинал'));
    await tester.pump();
    final original = find.text(
      'Rewatching in 2026 and it still hits different',
    );
    expect(original, findsOneWidget);
    expect(
      tester.getTopLeft(original).dy,
      lessThan(tester.getTopLeft(find.text(translated)).dy),
    );
    await tester.tap(find.text('Скрыть оригинал'));
    await tester.pump();
    expect(original, findsNothing);

    // Кэш на сессию: после смены вкладки перевод без нового запроса.
    await tester.tap(find.text('Описание'));
    await UiHarness.settle(tester);
    await tester.tap(find.text('Комментарии'));
    await UiHarness.settle(tester);
    expect(find.text(translated), findsOneWidget);
    expect(h.translateRequests, hasLength(1));

    // Согласие запомнено: второго вопроса нет.
    expect(
      await UiHarness.run(tester, h.services.preferences.myMemoryConsent),
      isTrue,
    );
    await h.dispose(tester);
  });

  testWidgets('quota exceeded and network error show a message', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.services.preferences.setMyMemoryConsent(true),
    );
    h.translateHandler = (_) => http.Response.bytes(
      utf8.encode(jsonEncode({'quotaFinished': true, 'responseStatus': 429})),
      200,
    );
    await openComments(tester);
    await tapTranslate(tester);
    expect(
      find.text('Лимит перевода исчерпан. Попробуйте завтра'),
      findsOneWidget,
    );
    await h.dispose(tester);
  });

  testWidgets('network error does not crash and keeps the button', (
    tester,
  ) async {
    await tester.runAsync(
      () => h.services.preferences.setMyMemoryConsent(true),
    );
    h.translateHandler = (_) => throw http.ClientException('offline');
    await openComments(tester);
    await tapTranslate(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Не удалось перевести. Проверьте подключение к интернету'),
      findsOneWidget,
    );
    expect(find.text('Перевести на русский'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('on device: no consent, language pack progress', (tester) async {
    final engine = _DeviceEngine();
    h.translationEngine = engine;
    await openComments(tester);
    await tester.ensureVisible(find.text('Перевести на русский'));
    await tester.tap(find.text('Перевести на русский'));
    await tester.pump();
    expect(find.text('Перевод через MyMemory'), findsNothing);
    expect(find.text('Загружаем языковой пакет…'), findsOneWidget);
    engine.download.complete();
    await UiHarness.settle(tester);
    expect(
      find.text(
        'На устройстве: Rewatching in 2026 and it still hits different',
      ),
      findsOneWidget,
    );
    expect(find.text('Перевод на русский'), findsOneWidget);
    await h.dispose(tester);
  });
}
