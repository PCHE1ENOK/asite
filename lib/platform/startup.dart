/// Подготовка, зависящая от платформы: на ПК и телефонах — дисковый кэш
/// картинок, в браузере — ничего (картинки кэширует браузер).
library;

export 'startup_io.dart' if (dart.library.js_interop) 'startup_web.dart';
