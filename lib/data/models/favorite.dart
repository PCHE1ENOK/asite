/// Отметка «Понравилось» — независимо от статуса в списках. Снятая
/// отметка хранится с [deleted] = true, чтобы дойти до других устройств.
class Favorite {
  const Favorite({
    required this.mediaId,
    required this.updatedAt,
    this.deleted = false,
  });

  final int mediaId;
  final DateTime updatedAt;
  final bool deleted;

  static Favorite? tryFromJson(Map<String, dynamic> j) {
    final id = j['mediaId'];
    final at = DateTime.tryParse(j['updatedAt'] as String? ?? '');
    if (id is! int || at == null) return null;
    return Favorite(
      mediaId: id,
      updatedAt: at.toUtc(),
      deleted: j['deleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  @override
  bool operator ==(Object other) =>
      other is Favorite &&
      other.mediaId == mediaId &&
      other.updatedAt.isAtSameMomentAs(updatedAt) &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(mediaId, updatedAt.millisecondsSinceEpoch, deleted);
}
