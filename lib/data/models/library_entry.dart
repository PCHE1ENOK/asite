/// Статус тайтла в списках пользователя; значения как в AniList
/// `MediaListStatus`.
enum ListStatus {
  current('CURRENT'),
  planning('PLANNING'),
  completed('COMPLETED'),
  paused('PAUSED'),
  dropped('DROPPED'),
  repeating('REPEATING');

  const ListStatus(this.apiValue);

  final String apiValue;

  static ListStatus? fromApi(String? value) {
    for (final s in values) {
      if (s.apiValue == value) return s;
    }
    return null;
  }
}

/// Запись в списках пользователя.
///
/// Удаление хранится как запись с [deleted] = true, чтобы оно доходило до
/// других устройств при слиянии.
class LibraryEntry {
  const LibraryEntry({
    required this.mediaId,
    required this.status,
    required this.updatedAt,
    this.progress = 0,
    this.score,
    this.deleted = false,
  });

  final int mediaId;
  final ListStatus status;

  /// Количество просмотренных серий.
  final int progress;

  /// Оценка пользователя 1–10.
  final int? score;

  /// Время последнего изменения, UTC с точностью до миллисекунд.
  final DateTime updatedAt;
  final bool deleted;

  LibraryEntry copyWith({
    ListStatus? status,
    int? progress,
    int? Function()? score,
    DateTime? updatedAt,
    bool? deleted,
  }) => LibraryEntry(
    mediaId: mediaId,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    score: score == null ? this.score : score(),
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  /// Возвращает `null`, если запись повреждена (например, неизвестный
  /// статус от более новой версии приложения).
  static LibraryEntry? tryFromJson(Map<String, dynamic> json) {
    final id = json['mediaId'];
    final status = ListStatus.fromApi(json['status'] as String?);
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id is! int || status == null || updatedAt == null) return null;
    return LibraryEntry(
      mediaId: id,
      status: status,
      progress: json['progress'] as int? ?? 0,
      score: json['score'] as int?,
      updatedAt: updatedAt.toUtc(),
      deleted: json['deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'status': status.apiValue,
    'progress': progress,
    if (score != null) 'score': score,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  @override
  bool operator ==(Object other) =>
      other is LibraryEntry &&
      other.mediaId == mediaId &&
      other.status == status &&
      other.progress == progress &&
      other.score == score &&
      other.updatedAt.isAtSameMomentAs(updatedAt) &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
    mediaId,
    status,
    progress,
    score,
    updatedAt.millisecondsSinceEpoch,
    deleted,
  );

  @override
  String toString() =>
      'LibraryEntry($mediaId, ${status.apiValue}, $progress, '
      '${updatedAt.toIso8601String()}${deleted ? ', deleted' : ''})';
}
