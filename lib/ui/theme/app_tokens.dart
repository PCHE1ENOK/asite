import 'package:flutter/material.dart';

import '../../data/models/library_entry.dart';

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
    required this.status,
    required this.shadowE1,
    required this.shadowE2,
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

  /// Цвета статусов списка (`REPEATING` — как `CURRENT`).
  final Map<ListStatus, Color> status;
  final List<BoxShadow> shadowE1;
  final List<BoxShadow> shadowE2;

  static const adultBg = Color(0xFFB9302F);
  static const adultFg = Color(0xFFFFFFFF);

  /// Тёмная подложка бейджей на постере.
  static const posterBadgeBg = Color(0xA0000000);

  static const dark = AppTokens(
    bg: Color(0xFF0E1016),
    surface1: Color(0xFF161923),
    surface2: Color(0xFF1E2230),
    surface3: Color(0xFF272C3D),
    border: Color(0xFF2C3144),
    borderStrong: Color(0xFF3B4159),
    fg: Color(0xFFECEEF5),
    fg2: Color(0xFFA7ADC0),
    fg3: Color(0xFF878EA4),
    accent: Color(0xFF8399FF),
    accentHover: Color(0xFF9AACFF),
    accentPressed: Color(0xFF6F86F2),
    onAccent: Color(0xFF0E1016),
    accentSoft: Color(0x268399FF),
    highlight: Color(0xFFF2B544),
    good: Color(0xFF4CC38A),
    warn: Color(0xFFE3A73B),
    bad: Color(0xFFF27B7B),
    scrim: Color(0xB3000000),
    skeleton: Color(0xFF1E2230),
    skeletonShine: Color(0xFF272C3D),
    status: {
      ListStatus.current: Color(0xFF3987E5),
      ListStatus.repeating: Color(0xFF3987E5),
      ListStatus.planning: Color(0xFFD95926),
      ListStatus.completed: Color(0xFF199E70),
      ListStatus.paused: Color(0xFFC98500),
      ListStatus.dropped: Color(0xFFD55181),
    },
    shadowE1: [
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowE2: [
      BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 24),
    ],
  );

  static const light = AppTokens(
    bg: Color(0xFFF4F5F9),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFE9EBF2),
    surface3: Color(0xFFDEE1EA),
    border: Color(0xFFD9DCE6),
    borderStrong: Color(0xFFBFC3D1),
    fg: Color(0xFF141722),
    fg2: Color(0xFF474D62),
    fg3: Color(0xFF646A80),
    accent: Color(0xFF3150C9),
    accentHover: Color(0xFF2944B3),
    accentPressed: Color(0xFF22399A),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x1F3150C9),
    highlight: Color(0xFF94580A),
    good: Color(0xFF126F48),
    warn: Color(0xFF94580A),
    bad: Color(0xFFB9302F),
    scrim: Color(0xB3000000),
    skeleton: Color(0xFFE9EBF2),
    skeletonShine: Color(0xFFF4F5F9),
    status: {
      ListStatus.current: Color(0xFF2A78D6),
      ListStatus.repeating: Color(0xFF2A78D6),
      ListStatus.planning: Color(0xFFEB6834),
      ListStatus.completed: Color(0xFF1BAF7A),
      ListStatus.paused: Color(0xFFEDA100),
      ListStatus.dropped: Color(0xFFE87BA4),
    },
    shadowE1: [
      BoxShadow(color: Color(0x1A141722), offset: Offset(0, 1), blurRadius: 2),
    ],
    shadowE2: [
      BoxShadow(color: Color(0x24141722), offset: Offset(0, 8), blurRadius: 24),
    ],
  );

  /// Цвет оценки AniList (0–100): ≥75 good, 60–74 warn, <60 bad.
  Color scoreColor(int? score) => switch (score) {
    null => fg3,
    >= 75 => good,
    >= 60 => warn,
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
