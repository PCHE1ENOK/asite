import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Дисковый кэш картинок (обложки, баннеры, аватары): файл на URL в
/// каталоге кэша приложения. Размер ограничен [maxBytes]: при превышении
/// удаляются давно не открывавшиеся файлы.
///
/// Свой, а не `cached_network_image`: тот хранит сведения в sqflite,
/// которого нет на Windows без дополнительной настройки.
class ImageDiskCache {
  ImageDiskCache(
    this.dir, {
    this.maxBytes = defaultMaxBytes,
    http.Client? client,
  }) : _http = client ?? http.Client();

  static const defaultMaxBytes = 200 * 1024 * 1024;

  /// Кэш приложения; `null` — картинки только из сети (тесты).
  static ImageDiskCache? instance;

  final Directory dir;
  final int maxBytes;
  final http.Client _http;
  final _inFlight = <String, Future<Uint8List>>{};
  int _writtenSinceTrim = 0;

  /// Имя файла по URL (FNV-1a, 64 бита).
  static String fileName(String url) {
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h *= 0x100000001b3; // переполнение 64 бит — часть алгоритма
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex((h >> 32) & 0xFFFFFFFF)}${hex(h & 0xFFFFFFFF)}.img';
  }

  File _file(String url) => File(p.join(dir.path, fileName(url)));

  /// Байты картинки: с диска или из сети (с сохранением на диск).
  Future<Uint8List> get(String url) => _inFlight[url] ??= _get(url)
      // Не `=> remove(url)`: whenComplete ждал бы возвращённое будущее,
      // то есть самого себя.
      .whenComplete(() {
        _inFlight.remove(url);
      });

  Future<Uint8List> _get(String url) async {
    final f = _file(url);
    try {
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        // Отметка «недавно открывали» — для вытеснения старых.
        unawaited(f.setLastModified(DateTime.now()).catchError((Object _) {}));
        if (bytes.isNotEmpty) return bytes;
      }
    } on FileSystemException {
      // Повреждённый или занятый файл — скачаем заново.
    }
    final res = await _http.get(Uri.parse(url));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final bytes = res.bodyBytes;
    unawaited(_save(f, bytes));
    return bytes;
  }

  Future<void> _save(File f, Uint8List bytes) async {
    try {
      await dir.create(recursive: true);
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      _writtenSinceTrim += bytes.length;
      if (_writtenSinceTrim > maxBytes ~/ 10) {
        _writtenSinceTrim = 0;
        await trim();
      }
    } on FileSystemException {
      // Нет места или прав — картинка всё равно показана из памяти.
    }
  }

  /// Удаляет давно не открывавшиеся файлы, пока кэш больше [maxBytes]
  /// (оставляет 80 %, чтобы не чистить на каждой записи).
  Future<void> trim() async {
    if (!await dir.exists()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      try {
        final st = await e.stat();
        files.add((e, st.size, st.modified));
        total += st.size;
      } on FileSystemException {
        continue;
      }
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    final target = maxBytes * 8 ~/ 10;
    for (final (f, size, _) in files) {
      if (total <= target) break;
      try {
        await f.delete();
        total -= size;
      } on FileSystemException {
        continue;
      }
    }
  }

  /// Размер кэша на диске, байт.
  Future<int> size() async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
