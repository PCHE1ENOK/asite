import 'dart:convert';

import '../models/favorite.dart';
import '../models/library_entry.dart';
import '../models/title_note.dart';

/// Содержимое файла Gist: списки, заметки и «Понравилось».
class LibraryFile {
  const LibraryFile({
    this.entries = const [],
    this.notes = const [],
    this.favorites = const [],
  });

  final List<LibraryEntry> entries;
  final List<TitleNote> notes;
  final List<Favorite> favorites;
}

/// Формат файла списков в Gist.
abstract final class LibraryCodec {
  static const fileName = 'anime-viewer-library.json';
  static const description = 'Anime Viewer: списки пользователя';

  /// 2 — добавлено поле `notes` (заметки о тайтлах); 3 — `favorites`
  /// («Понравилось»). Файлы старых версий читаются без этих полей, а старая
  /// версия приложения неизвестные поля пропускает.
  static const version = 3;

  static String encode(
    List<LibraryEntry> entries, {
    List<TitleNote> notes = const [],
    List<Favorite> favorites = const [],
  }) => const JsonEncoder.withIndent('  ').convert({
    'app': 'anime_viewer',
    'version': version,
    'entries': [for (final e in entries) e.toJson()],
    'notes': [for (final n in notes) n.toJson()],
    'favorites': [for (final f in favorites) f.toJson()],
  });

  /// Только записи списков.
  static List<LibraryEntry> decode(String? content) =>
      decodeFile(content).entries;

  /// Пустой или повреждённый файл даёт пустое содержимое; некорректные
  /// записи пропускаются.
  static LibraryFile decodeFile(String? content) {
    if (content == null || content.trim().isEmpty) return const LibraryFile();
    final Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException {
      return const LibraryFile();
    }
    if (json is! Map) return const LibraryFile();
    final entries = json['entries'];
    final notes = json['notes'];
    final favorites = json['favorites'];
    return LibraryFile(
      entries: [
        if (entries is List)
          for (final e in entries)
            if (e is Map<String, dynamic>) ?LibraryEntry.tryFromJson(e),
      ],
      notes: [
        if (notes is List)
          for (final n in notes)
            if (n is Map<String, dynamic>) ?TitleNote.tryFromJson(n),
      ],
      favorites: [
        if (favorites is List)
          for (final f in favorites)
            if (f is Map<String, dynamic>) ?Favorite.tryFromJson(f),
      ],
    );
  }
}
