import 'dart:convert';

import 'package:anime_viewer/data/translation/translation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

class _CountingEngine implements TranslationEngine {
  int calls = 0;

  @override
  String? get server => null;

  @override
  Future<bool> needsPack(String? source) async => false;

  @override
  Future<bool> downloadPack(String? source) async => true;

  @override
  Future<TranslationResult> translate(String text, {String? source}) async {
    calls++;
    return Translated('ru:$text');
  }

  @override
  Future<void> close() async {}
}

class _BrokenDetector implements LanguageDetector {
  @override
  Future<String?> detect(String text) => Future.error(StateError('no model'));
}

void main() {
  test('language labels', () {
    expect(languageTag('en'), 'англ.');
    expect(languageFrom('ja'), 'с японского');
    expect(languageTag(null), isNull);
    expect(languageFrom('xx'), isNull);
  });

  group('ScriptLanguageDetector', () {
    const d = ScriptLanguageDetector();
    test('russian, other cyrillic, latin, japanese', () async {
      expect(await d.detect('Отличная серия, музыка — мурашки'), 'ru');
      expect(await d.detect('Дуже гарна серія, і музика'), isNull);
      expect(await d.detect('Rewatching in 2026 and it still hits'), isNull);
      expect(await d.detect('このシーンは最高だった'), 'ja');
      expect(await d.detect('12345 !!!'), isNull);
    });
  });

  group('CommentTranslator', () {
    test('caches translations for the session', () async {
      final engine = _CountingEngine();
      final t = CommentTranslator(
        detector: const ScriptLanguageDetector(),
        engine: engine,
      );
      expect(t.cached('Hello'), isNull);
      expect((await t.translate('Hello') as Translated).text, 'ru:Hello');
      expect((await t.translate('Hello') as Translated).text, 'ru:Hello');
      expect(engine.calls, 1);
      expect(t.cached('Hello'), 'ru:Hello');
    });

    test('button only for non-russian; detection failure keeps it', () async {
      final t = CommentTranslator(
        detector: const ScriptLanguageDetector(),
        engine: _CountingEngine(),
      );
      expect(await t.canTranslate('Привет, это русский текст'), isFalse);
      expect(await t.canTranslate('Hello there'), isTrue);
      final broken = CommentTranslator(
        detector: _BrokenDetector(),
        engine: _CountingEngine(),
      );
      expect(await broken.canTranslate('Привет'), isTrue);
    });
  });

  group('MyMemoryEngine', () {
    late Map<String, int> usage;
    late List<Uri> requests;

    MyMemoryEngine engine(
      Future<http.Response> Function(http.Request) handler, {
      int limit = 5000,
    }) => MyMemoryEngine(
      usage: (day) async => usage[day] ?? 0,
      saveUsage: (day, n) async => usage[day] = n,
      clock: () => DateTime.utc(2026, 10, 30, 12),
      dailyLimit: limit,
      httpClient: MockClient((r) {
        requests.add(r.url);
        return handler(r);
      }),
    );

    setUp(() {
      usage = {};
      requests = [];
    });

    test('translates and counts characters', () async {
      final e = engine(
        (_) async => json({
          'responseStatus': 200,
          'responseData': {
            'translatedText': 'Привет &quot;мир&quot; &amp; всё',
          },
        }),
      );
      final r = await e.translate('Hello "world" & all', source: 'en');
      expect((r as Translated).text, 'Привет "мир" & всё');
      expect(requests.single.queryParameters['langpair'], 'en|ru');
      expect(usage['2026-10-30'], 'Hello "world" & all'.length);

      await e.translate('Hola');
      expect(requests.last.queryParameters['langpair'], 'Autodetect|ru');
    });

    test('local daily limit: no request when it would be exceeded', () async {
      usage['2026-10-30'] = 4990;
      final e = engine((_) async => fail('no request expected'));
      expect(
        await e.translate('This is longer than ten'),
        isA<TranslationQuotaExceeded>(),
      );
      expect(requests, isEmpty);
    });

    test('server quota signals', () async {
      for (final res in [
        json({'quotaFinished': true, 'responseStatus': 200}),
        json({
          'responseStatus': '429',
          'responseData': {
            'translatedText':
                'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS',
          },
        }),
        http.Response('', 429),
      ]) {
        usage = {};
        final e = engine((_) async => res);
        expect(await e.translate('Hello'), isA<TranslationQuotaExceeded>());
        expect(usage['2026-10-30'], 5000, reason: 'no more requests today');
      }
    });

    test('network error and bad answers do not throw', () async {
      final e = engine((_) async => throw http.ClientException('offline'));
      final r = await e.translate('Hello');
      expect(r, isA<TranslationFailed>());
      expect((r as TranslationFailed).message, translationOfflineMessage);
      final bad = engine((_) async => http.Response('not json', 200));
      expect(await bad.translate('Hello'), isA<TranslationFailed>());
    });

    test('long text is split into parts of at most 500 bytes', () {
      final text = List.filled(120, 'Слово').join(' ');
      final parts = MyMemoryEngine.splitForQuery(text);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(utf8.encode(p).length, lessThanOrEqualTo(500));
      }
      expect(parts.join(' '), text);
      final long = MyMemoryEngine.splitForQuery('я' * 600);
      expect(long.join(), 'я' * 600);
      expect(long.every((p) => utf8.encode(p).length <= 500), isTrue);
    });
  });
}
