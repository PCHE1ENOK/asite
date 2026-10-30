/// Вердикт в заметке о тайтле.
enum NoteVerdict {
  none('NONE'),
  rewatch('REWATCH'),
  recommend('RECOMMEND'),
  notRecommend('NOT_RECOMMEND');

  const NoteVerdict(this.apiValue);

  final String apiValue;

  static NoteVerdict fromApi(String? v) =>
      values.where((e) => e.apiValue == v).firstOrNull ?? none;
}

/// Запомнившийся момент: серия, необязательный таймкод и текст.
class NoteMoment {
  const NoteMoment({required this.episode, this.timecode, required this.text});

  final int episode;

  /// Позиция в серии.
  final Duration? timecode;
  final String text;

  static NoteMoment? tryFromJson(Map<String, dynamic> j) {
    final episode = j['episode'];
    final text = j['text'];
    if (episode is! int || text is! String) return null;
    final t = j['timecode'];
    return NoteMoment(
      episode: episode,
      timecode: t is int ? Duration(seconds: t) : null,
      text: text,
    );
  }

  Map<String, dynamic> toJson() => {
    'episode': episode,
    if (timecode != null) 'timecode': timecode!.inSeconds,
    'text': text,
  };

  /// «12:34» или «1:02:03».
  String? get timecodeLabel {
    final t = timecode;
    if (t == null) return null;
    final h = t.inHours, m = t.inMinutes % 60, s = t.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  /// Разбирает «12:34», «1:02:03» или «754» (секунды); иначе `null`.
  static Duration? parseTimecode(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length > 3 || parts.any((p) => int.tryParse(p) == null)) {
      return null;
    }
    final nums = parts.map(int.parse).toList();
    var seconds = 0;
    for (final n in nums) {
      seconds = seconds * 60 + n;
    }
    if (nums.length > 1 && nums.skip(1).any((n) => n >= 60)) return null;
    return Duration(seconds: seconds);
  }

  @override
  bool operator ==(Object other) =>
      other is NoteMoment &&
      other.episode == episode &&
      other.timecode == timecode &&
      other.text == text;

  @override
  int get hashCode => Object.hash(episode, timecode, text);
}

/// Личная заметка о тайтле в профиле.
class TitleNote {
  const TitleNote({
    required this.mediaId,
    required this.updatedAt,
    this.summary = '',
    this.verdict = NoteVerdict.none,
    this.liked = '',
    this.dropReason = '',
    this.moments = const [],
    this.deleted = false,
  });

  final int mediaId;

  /// Краткий итог: одна-две строки для списков.
  final String summary;
  final NoteVerdict verdict;

  /// Что понравилось.
  final String liked;

  /// Причина, если брошено (до [maxDropReason] символов).
  final String dropReason;
  final List<NoteMoment> moments;
  final DateTime updatedAt;
  final bool deleted;

  static const maxDropReason = 500;
  static const maxSummary = 140;

  /// Подсказки для причины «брошено».
  static const dropReasonHints = [
    'Скучно',
    'Затянуто',
    'Не понравились персонажи',
    'Слабая история',
    'Другое',
  ];

  bool get isEmpty =>
      summary.trim().isEmpty &&
      verdict == NoteVerdict.none &&
      liked.trim().isEmpty &&
      dropReason.trim().isEmpty &&
      moments.isEmpty;

  TitleNote copyWith({
    String? summary,
    NoteVerdict? verdict,
    String? liked,
    String? dropReason,
    List<NoteMoment>? moments,
    DateTime? updatedAt,
    bool? deleted,
  }) => TitleNote(
    mediaId: mediaId,
    summary: summary ?? this.summary,
    verdict: verdict ?? this.verdict,
    liked: liked ?? this.liked,
    dropReason: dropReason ?? this.dropReason,
    moments: moments ?? this.moments,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  static TitleNote? tryFromJson(Map<String, dynamic> j) {
    final id = j['mediaId'];
    final updatedAt = DateTime.tryParse(j['updatedAt'] as String? ?? '');
    if (id is! int || updatedAt == null) return null;
    return TitleNote(
      mediaId: id,
      summary: j['summary'] as String? ?? '',
      verdict: NoteVerdict.fromApi(j['verdict'] as String?),
      liked: j['liked'] as String? ?? '',
      dropReason: j['dropReason'] as String? ?? '',
      moments: [
        for (final m in (j['moments'] as List? ?? const []))
          if (m is Map<String, dynamic>) ?NoteMoment.tryFromJson(m),
      ],
      updatedAt: updatedAt.toUtc(),
      deleted: j['deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    if (summary.isNotEmpty) 'summary': summary,
    if (verdict != NoteVerdict.none) 'verdict': verdict.apiValue,
    if (liked.isNotEmpty) 'liked': liked,
    if (dropReason.isNotEmpty) 'dropReason': dropReason,
    if (moments.isNotEmpty) 'moments': [for (final m in moments) m.toJson()],
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  @override
  bool operator ==(Object other) =>
      other is TitleNote &&
      other.mediaId == mediaId &&
      other.summary == summary &&
      other.verdict == verdict &&
      other.liked == liked &&
      other.dropReason == dropReason &&
      _listEq(other.moments, moments) &&
      other.updatedAt.isAtSameMomentAs(updatedAt) &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
    mediaId,
    summary,
    verdict,
    liked,
    dropReason,
    Object.hashAll(moments),
    updatedAt.millisecondsSinceEpoch,
    deleted,
  );

  static bool _listEq(List<NoteMoment> a, List<NoteMoment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
