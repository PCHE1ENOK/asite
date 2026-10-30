import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Результат перевода комментария.
sealed class TranslationResult {
  const TranslationResult();
}

class Translated extends TranslationResult {
  const Translated(this.text);

  final String text;
}

/// Дневной лимит бесплатного сервиса исчерпан.
class TranslationQuotaExceeded extends TranslationResult {
  const TranslationQuotaExceeded();
}

class TranslationFailed extends TranslationResult {
  const TranslationFailed(this.message);

  /// Текст для пользователя.
  final String message;
}

/// Этап перевода — для подписи в интерфейсе.
enum TranslationStage {
  /// Скачивается языковой пакет (только перевод на устройстве).
  downloadingModel,
  translating,
}

/// Определение языка текста. `null` — определить не удалось.
abstract interface class LanguageDetector {
  Future<String?> detect(String text);
}

/// Переводчик на русский.
abstract interface class TranslationEngine {
  /// Сервер, куда уходит текст; `null` — перевод на устройстве.
  String? get server;

  /// [source] — код языка (BCP-47) или `null`, если неизвестен.
  Future<TranslationResult> translate(
    String text, {
    String? source,
    void Function(TranslationStage stage)? onStage,
  });

  Future<void> close();
}

/// Определение языка по алфавиту — запасной вариант без ML Kit (Windows).
///
/// Уверенно отличает только русский от явно других письменностей;
/// для латиницы возвращает `null` (кнопка «Перевести» остаётся).
class ScriptLanguageDetector implements LanguageDetector {
  const ScriptLanguageDetector();

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _cyrillic = RegExp(r'\p{Script=Cyrillic}', unicode: true);
  static final _kana = RegExp(
    r'[\p{Script=Hiragana}\p{Script=Katakana}]',
    unicode: true,
  );
  static final _hangul = RegExp(r'\p{Script=Hangul}', unicode: true);
  static final _han = RegExp(r'\p{Script=Han}', unicode: true);

  /// Буквы украинского, белорусского и т. п., которых нет в русском.
  static final _notRussian = RegExp('[іїєґўІЇЄҐЎ]');

  @override
  Future<String?> detect(String text) async {
    final letters = _letter.allMatches(text).length;
    if (letters == 0) return null;
    double share(RegExp r) => r.allMatches(text).length / letters;
    if (share(_cyrillic) > 0.6) {
      return _notRussian.hasMatch(text) ? null : 'ru';
    }
    if (share(_kana) > 0.1) return 'ja';
    if (share(_hangul) > 0.5) return 'ko';
    if (share(_han) > 0.5) return 'zh';
    return null;
  }
}

/// Перевод комментариев: определение языка и перевод с кэшем на сессию
/// (в базу ничего не пишется).
class CommentTranslator {
  CommentTranslator({required this.detector, required this.engine});

  final LanguageDetector detector;
  final TranslationEngine engine;

  final _languages = <String, String?>{};
  final _translations = <String, String>{};

  /// Сервер, куда уходит текст (`null` — на устройстве).
  String? get server => engine.server;

  /// Уже определённый язык текста (без запроса).
  String? knownLanguage(String text) => _languages[text];

  /// Язык текста; ошибка определения — `null`.
  Future<String?> language(String text) async {
    if (_languages.containsKey(text)) return _languages[text];
    String? lang;
    try {
      lang = await detector.detect(text);
    } catch (_) {
      lang = null;
    }
    return _languages[text] = lang;
  }

  /// Кнопку «Перевести на русский» прячем только у русских комментариев.
  Future<bool> canTranslate(String text) async =>
      text.trim().isNotEmpty && await language(text) != 'ru';

  /// Перевод из кэша сессии.
  String? cached(String text) => _translations[text];

  Future<TranslationResult> translate(
    String text, {
    void Function(TranslationStage stage)? onStage,
  }) async {
    if (_translations[text] case final t?) return Translated(t);
    final TranslationResult r;
    try {
      r = await engine.translate(
        text,
        source: await language(text),
        onStage: onStage,
      );
    } catch (_) {
      return const TranslationFailed(
        'Не удалось перевести. Проверьте подключение к интернету',
      );
    }
    if (r is Translated) _translations[text] = r.text;
    return r;
  }

  Future<void> close() => engine.close();
}

/// Бесплатный MyMemory без регистрации — для ПК, где нет ML Kit.
///
/// Текст уходит на сервер MyMemory, поэтому интерфейс сначала спрашивает
/// согласие. Анонимный лимит — [dailyLimit] символов в день: считаем
/// отправленное сами и не делаем запрос, если он превысит лимит.
class MyMemoryEngine implements TranslationEngine {
  MyMemoryEngine({
    required this.usage,
    required this.saveUsage,
    http.Client? httpClient,
    DateTime Function()? clock,
    this.dailyLimit = 5000,
  }) : _http = httpClient ?? http.Client(),
       _now = clock ?? DateTime.now;

  static const endpoint = 'https://api.mymemory.translated.net/get';

  /// Больше за один запрос сервис не принимает (байт UTF-8).
  static const maxQueryBytes = 500;

  final Future<int> Function(String day) usage;
  final Future<void> Function(String day, int chars) saveUsage;
  final int dailyLimit;
  final http.Client _http;
  final DateTime Function() _now;

  @override
  String get server => 'MyMemory';

  String _day() {
    final d = _now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Future<TranslationResult> translate(
    String text, {
    String? source,
    void Function(TranslationStage stage)? onStage,
  }) async {
    final day = _day();
    var used = await usage(day);
    if (used + text.length > dailyLimit) {
      return const TranslationQuotaExceeded();
    }
    onStage?.call(TranslationStage.translating);
    final out = StringBuffer();
    for (final chunk in splitForQuery(text)) {
      final http.Response res;
      try {
        res = await _http
            .get(
              Uri.parse(endpoint).replace(
                queryParameters: {
                  'q': chunk,
                  'langpair': '${source ?? 'Autodetect'}|ru',
                },
              ),
            )
            .timeout(const Duration(seconds: 15));
      } on Object {
        return const TranslationFailed(
          'Не удалось перевести. Проверьте подключение к интернету',
        );
      }
      used += chunk.length;
      await saveUsage(day, used);
      final r = parseResponse(res);
      if (r is! Translated) {
        // Сервер сказал, что лимит исчерпан, — больше сегодня не спрашиваем.
        if (r is TranslationQuotaExceeded) await saveUsage(day, dailyLimit);
        return r;
      }
      if (out.isNotEmpty) out.write(' ');
      out.write(r.text);
    }
    return Translated(out.toString());
  }

  /// Разбирает ответ MyMemory, включая признаки исчерпанного лимита.
  static TranslationResult parseResponse(http.Response res) {
    if (res.statusCode == 429) return const TranslationQuotaExceeded();
    if (res.statusCode != 200) {
      return const TranslationFailed('Сервис перевода не ответил');
    }
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final status = '${j['responseStatus']}';
      final text =
          (j['responseData'] as Map<String, dynamic>?)?['translatedText']
              as String?;
      if (j['quotaFinished'] == true ||
          status == '429' ||
          (text?.startsWith('MYMEMORY WARNING') ?? false)) {
        return const TranslationQuotaExceeded();
      }
      if (status != '200' || text == null || text.trim().isEmpty) {
        return const TranslationFailed('Сервис перевода не ответил');
      }
      return Translated(_unescape(text));
    } on Object {
      return const TranslationFailed('Сервис перевода не ответил');
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  /// Делит текст на части не длиннее [maxQueryBytes] байт, по границам
  /// предложений и слов, где можно.
  static List<String> splitForQuery(String text) {
    int bytes(String s) => utf8.encode(s).length;
    final parts = <String>[];
    var cur = '';
    void flush() {
      if (cur.trim().isNotEmpty) parts.add(cur.trim());
      cur = '';
    }

    for (final word in text.split(RegExp(r'(?<=\s)'))) {
      if (bytes(cur + word) <= maxQueryBytes) {
        cur += word;
        continue;
      }
      flush();
      // Одно «слово» длиннее лимита — режем по символам.
      var w = word;
      while (bytes(w) > maxQueryBytes) {
        var n = w.length;
        while (bytes(w.substring(0, n)) > maxQueryBytes) {
          n--;
        }
        parts.add(w.substring(0, n));
        w = w.substring(n);
      }
      cur = w;
    }
    flush();
    return parts;
  }

  @override
  Future<void> close() async => _http.close();
}
