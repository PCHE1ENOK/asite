import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/library/library_repository.dart';
import '../data/models/library_entry.dart';

/// Текущие списки пользователя в памяти: статус и прогресс по id тайтла
/// для постеров, кнопки статуса и фильтра каталога.
class LibraryIndex extends ChangeNotifier {
  LibraryIndex(this.repository) {
    _sub = repository.watchEntries().listen((entries) {
      _entries = {for (final e in entries) e.mediaId: e};
      _loaded = true;
      notifyListeners();
    });
  }

  final LibraryRepository repository;
  late final StreamSubscription<List<LibraryEntry>> _sub;
  Map<int, LibraryEntry> _entries = const {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  LibraryEntry? operator [](int mediaId) => _entries[mediaId];
  Iterable<LibraryEntry> get entries => _entries.values;
  Set<int> get ids => _entries.keys.toSet();

  /// Количество тайтлов по статусам; «Пересматриваю» считается в «Смотрю».
  Map<ListStatus, int> get counts {
    final c = <ListStatus, int>{};
    for (final e in _entries.values) {
      final s = e.status == ListStatus.repeating
          ? ListStatus.current
          : e.status;
      c[s] = (c[s] ?? 0) + 1;
    }
    return c;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
