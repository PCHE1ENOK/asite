import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translation.dart';

/// Определение языка ML Kit на устройстве (Android, iOS).
class MlKitLanguageDetector implements LanguageDetector {
  final _id = LanguageIdentifier(confidenceThreshold: 0.5);

  @override
  Future<String?> detect(String text) async {
    final lang = await _id.identifyLanguage(text);
    return lang == 'und' ? null : lang;
  }

  Future<void> close() => _id.close();
}

/// Перевод ML Kit на устройстве: ключ не нужен, текст не покидает
/// устройство. Языковой пакет (~30 МБ) скачивается по кнопке перед первым
/// переводом с этого языка — в том числе по мобильной сети.
class MlKitEngine implements TranslationEngine {
  MlKitEngine({this.detector});

  /// Закрывается вместе с переводчиком.
  final MlKitLanguageDetector? detector;
  final _models = OnDeviceTranslatorModelManager();
  final _translators = <TranslateLanguage, OnDeviceTranslator>{};

  @override
  String? get server => null;

  static TranslateLanguage? _language(String? code) {
    if (code == null) return null;
    final base = code.split(RegExp('[-_]')).first.toLowerCase();
    return TranslateLanguage.values.where((l) => l.bcpCode == base).firstOrNull;
  }

  @override
  Future<bool> needsPack(String? source) async {
    final from = _language(source);
    if (from == null || from == TranslateLanguage.russian) return false;
    for (final lang in [from, TranslateLanguage.russian]) {
      if (!await _models.isModelDownloaded(lang.bcpCode)) return true;
    }
    return false;
  }

  /// ML Kit не сообщает процент — интерфейс показывает неопределённый
  /// прогресс.
  @override
  Future<bool> downloadPack(String? source) async {
    final from = _language(source);
    if (from == null) return false;
    for (final lang in [from, TranslateLanguage.russian]) {
      if (await _models.isModelDownloaded(lang.bcpCode)) continue;
      if (!await _models.downloadModel(lang.bcpCode, isWifiRequired: false)) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<TranslationResult> translate(String text, {String? source}) async {
    final from = _language(source);
    if (from == null) {
      return const TranslationFailed(
        'Не удалось определить язык комментария для перевода на устройстве',
      );
    }
    if (from == TranslateLanguage.russian) return Translated(text);
    final translator = _translators[from] ??= OnDeviceTranslator(
      sourceLanguage: from,
      targetLanguage: TranslateLanguage.russian,
    );
    return Translated(await translator.translateText(text));
  }

  @override
  Future<void> close() async {
    for (final t in _translators.values) {
      await t.close();
    }
    _translators.clear();
    await detector?.close();
  }
}
