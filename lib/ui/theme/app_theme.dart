import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Типографика из `design/tokens.json`.
abstract final class AppText {
  static const display = 'Unbounded';
  static const text = 'Golos Text';
  static const fallback = ['Segoe UI Variable', 'SF Pro Text', 'Roboto'];
  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle _t(
    String family,
    double size,
    double line,
    FontWeight weight, {
    double tracking = 0,
    bool tabularFigures = false,
  }) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    height: line / size,
    fontWeight: weight,
    letterSpacing: tracking,
    fontFeatures: tabularFigures ? tabular : null,
  );

  static final displayStyle = _t(
    display,
    32,
    40,
    FontWeight.w600,
    tracking: -0.5,
  );
  static final headline = _t(display, 22, 28, FontWeight.w600, tracking: -0.2);
  static final title = _t(text, 18, 24, FontWeight.w600);
  static final body = _t(text, 15, 22, FontWeight.w400);
  static final bodyStrong = _t(text, 15, 22, FontWeight.w600);
  static final label = _t(text, 13, 18, FontWeight.w500);
  static final labelStrong = _t(text, 13, 18, FontWeight.w600);
  static final caption = _t(text, 12, 16, FontWeight.w400);
  static final overline = _t(text, 11, 14, FontWeight.w600, tracking: 0.8);
  static final scoreLg = _t(
    display,
    28,
    32,
    FontWeight.w600,
    tabularFigures: true,
  );
  static final badge = _t(text, 12, 16, FontWeight.w600, tabularFigures: true);
}

abstract final class AppTheme {
  static ThemeData build(Brightness brightness) {
    final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.accent,
      secondary: t.accent,
      onSecondary: t.onAccent,
      secondaryContainer: t.accentSoft,
      onSecondaryContainer: t.accent,
      error: t.bad,
      onError: t.onAccent,
      surface: t.bg,
      onSurface: t.fg,
      onSurfaceVariant: t.fg2,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface1,
      surfaceContainer: t.surface1,
      surfaceContainerHigh: t.surface2,
      surfaceContainerHighest: t.surface3,
      outline: t.borderStrong,
      outlineVariant: t.border,
      inverseSurface: t.surface3,
      onInverseSurface: t.fg,
      shadow: Colors.black,
      scrim: t.scrim,
    );

    final textTheme = TextTheme(
      displaySmall: AppText.displayStyle,
      headlineSmall: AppText.headline,
      titleLarge: AppText.title,
      titleMedium: AppText.bodyStrong,
      titleSmall: AppText.labelStrong,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.labelStrong,
      labelMedium: AppText.label,
      labelSmall: AppText.overline,
    ).apply(bodyColor: t.fg, displayColor: t.fg);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
    );
    WidgetStateProperty<Color?> overlay(Color base) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return base.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return base.withValues(alpha: 0.06);
          }
          return null;
        });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: AppText.text,
      fontFamilyFallback: AppText.fallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.border,
      extensions: [t],
      splashFactory: NoSplash.splashFactory,
      hoverColor: t.fg.withValues(alpha: 0.06),
      focusColor: t.fg.withValues(alpha: 0.06),
      highlightColor: t.fg.withValues(alpha: 0.12),
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.accent.withValues(alpha: 0.38),
          disabledForegroundColor: t.onAccent.withValues(alpha: 0.6),
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: AppText.labelStrong,
          shape: buttonShape,
        ).copyWith(overlayColor: overlay(t.onAccent)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.fg,
          side: BorderSide(color: t.borderStrong),
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: AppText.labelStrong,
          shape: buttonShape,
        ).copyWith(overlayColor: overlay(t.fg)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          minimumSize: const Size(48, 36),
          textStyle: AppText.labelStrong,
          shape: buttonShape,
        ).copyWith(overlayColor: overlay(t.accent)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: t.fg2,
          minimumSize: const Size(40, 40),
        ).copyWith(overlayColor: overlay(t.fg)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: t.accentSoft,
        disabledColor: Colors.transparent,
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.selected)
                ? Colors.transparent
                : t.border,
          ),
        ),
        shape: const StadiumBorder(),
        labelStyle: AppText.label.copyWith(color: t.fg),
        secondaryLabelStyle: AppText.label.copyWith(color: t.accent),
        checkmarkColor: t.accent,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface1,
        hintStyle: AppText.body.copyWith(color: t.fg3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: t.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: t.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: t.accent, width: 2),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: t.border),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surface2,
        surfaceTintColor: Colors.transparent,
        textStyle: AppText.label.copyWith(color: t.fg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: t.border),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.fg,
        unselectedLabelColor: t.fg2,
        labelStyle: AppText.bodyStrong,
        unselectedLabelStyle: AppText.body,
        indicatorColor: t.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: t.border,
        overlayColor: overlay(t.fg),
        tabAlignment: TabAlignment.start,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.bg,
        indicatorColor: t.accentSoft,
        selectedIconTheme: IconThemeData(color: t.accent, fill: 1),
        unselectedIconTheme: IconThemeData(color: t.fg2),
        selectedLabelTextStyle: AppText.caption.copyWith(color: t.fg),
        unselectedLabelTextStyle: AppText.caption.copyWith(color: t.fg2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface1,
        indicatorColor: t.accentSoft,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? IconThemeData(color: t.accent, fill: 1)
              : IconThemeData(color: t.fg2),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppText.caption.copyWith(
            color: s.contains(WidgetState.selected) ? t.fg : t.fg2,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surface3,
        contentTextStyle: AppText.label.copyWith(color: t.fg),
        actionTextColor: t.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: AppText.caption.copyWith(color: t.fg),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.fg2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.surface3,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : t.borderStrong,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: t.accentSoft,
          selectedForegroundColor: t.accent,
          foregroundColor: t.fg2,
          side: BorderSide(color: t.border),
          textStyle: AppText.label,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(t.fg3.withValues(alpha: 0.5)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.surface3,
      ),
    );
  }
}
