import 'package:flutter/material.dart';

import '../../data/models/library_entry.dart';

part 'app_tokens.g.dart';

/// Дизайн-токены темы «Ai» из `design/tokens.json`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.onAccent,
    required this.accentSoft,
    required this.highlight,
    required this.good,
    required this.warn,
    required this.bad,
    required this.scrim,
    required this.skeleton,
    required this.skeletonShine,
    required this.badgeGround,
    required this.status,
    required this.shadowE1,
    required this.shadowE2,
    required this.avatars,
    required this.titleBanner,
    required this.avatarGround,
    required this.avatarRing,
  });

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderStrong;
  final Color fg;
  final Color fg2;
  final Color fg3;
  final Color accent;
  final Color accentHover;
  final Color accentPressed;
  final Color onAccent;
  final Color accentSoft;
  final Color highlight;
  final Color good;
  final Color warn;
  final Color bad;
  final Color scrim;
  final Color skeleton;
  final Color skeletonShine;

  /// Подложка плашек на постере (оценка, статус, сердце, вердикт): светлая
  /// в светлой теме, тёмная в тёмной; текст на ней — good/warn/bad темы.
  final Color badgeGround;

  /// Высота баннера карточки тайтла.
  final double titleBanner;

  /// Цвета статусов списка (`REPEATING` — как `CURRENT`).
  final Map<ListStatus, Color> status;
  final List<BoxShadow> shadowE1;
  final List<BoxShadow> shadowE2;

  /// Цвета аватаров профилей; номер цвета профиля — индекс по модулю.
  final List<Color> avatars;

  Color avatar(int index) => avatars[index % avatars.length];

  /// Подложка под картинкой аватара GitHub и обводка 1 px внутрь
  /// (design/screens.md §9.1).
  final Color avatarGround;
  final Color avatarRing;

  static const adultBg = _adultBg;
  static const adultFg = _adultFg;

  /// Текст и значки на цветах аватаров (в обеих темах).
  static const onAvatar = Color(0xFFFFFFFF);

  /// Палитры из `design/tokens.json` (файл `app_tokens.g.dart` создаёт
  /// `dart run tool/gen_tokens.dart`).
  static const dark = _dark;
  static const light = _light;

  /// Цвет оценки 0–10: зелёный от 7,5, жёлтый 6,0–7,4, красный ниже.
  Color scoreColor(double? score) => switch (score) {
    null => fg3,
    >= 7.5 => good,
    >= 6.0 => warn,
    _ => bad,
  };

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Отступы, радиусы, брейкпоинты и анимации из токенов.
abstract final class AppSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;
}

abstract final class AppRadius {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class AppLayout {
  static const medium = 640.0;
  static const expanded = 1008.0;
  static const large = 1440.0;
  static const navRail = 72.0;
  static const navRailExpanded = 248.0;
  static const posterMin = 148.0;
  static const posterMax = 220.0;
  static const contentMaxWidth = 1600.0;

  static double gutter(double width) => width < medium
      ? 16
      : width < expanded
      ? 24
      : 32;

  static double posterGap(double width) => width < medium ? 12 : 20;
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 220);
  static const standard = Cubic(0.2, 0, 0, 1);
}

extension AppTokensContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
