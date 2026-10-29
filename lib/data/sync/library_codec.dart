import 'dart:convert';

import '../models/library_entry.dart';

/// Формат файла списков в Gist.
abstract final class LibraryCodec {
  static const fileName = 'anime-viewer-library.json';
  static const description = 'Anime Viewer: списки пользователя';
  static const version = 1;

  static String encode(List<LibraryEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'anime_viewer',
        'version': version,
        'entries': [for (final e in entries) e.toJson()],
      });

  /// Пустой или повреждённый файл даёт пустой список; некорректные
  /// записи пропускаются.
  static List<LibraryEntry> decode(String? content) {
    if (content == null || content.trim().isEmpty) return const [];
    final Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException {
      return const [];
    }
    final entries = json is Map ? json['entries'] : null;
    if (entries is! List) return const [];
    return [
      for (final e in entries)
        if (e is Map<String, dynamic>) ?LibraryEntry.tryFromJson(e),
    ];
  }
}
