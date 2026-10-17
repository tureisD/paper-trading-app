import 'package:flutter/widgets.dart';

/// The surface/text palette for one appearance.
///
/// Everything theme-dependent funnels through here, so flipping the palette
/// restyles the whole app without touching every widget.
class AppPalette {
  const AppPalette({
    required this.carbon,
    required this.panel,
    required this.raised,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.neutral,
  });

  /// Page background.
  final Color carbon;

  /// Elevated panel background.
  final Color panel;

  /// Slightly raised header/row fill.
  final Color raised;

  /// 1px structural border.
  final Color hairline;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Structural slate that must not imply direction.
  final Color neutral;

  /// Matte carbon — the institutional dark terminal.
  static const AppPalette dark = AppPalette(
    carbon: Color(0xFF0D0E11),
    panel: Color(0xFF13151A),
    raised: Color(0xFF181B21),
    hairline: Color(0xFF22252A),
    textPrimary: Color(0xFFE6E8EB),
    textSecondary: Color(0xFF9BA1A9),
    textMuted: Color(0xFF6B7178),
    neutral: Color(0xFF8A9199),
  );

  /// Crisp paper — the same layout on a light surface.
  static const AppPalette light = AppPalette(
    carbon: Color(0xFFF7F7F5),
    panel: Color(0xFFFFFFFF),
    raised: Color(0xFFF1F2F0),
    hairline: Color(0xFFE2E4E9),
    textPrimary: Color(0xFF15171A),
    textSecondary: Color(0xFF5A6069),
    textMuted: Color(0xFF8B929B),
    neutral: Color(0xFF6B7178),
  );
}

/// Institutional trading-terminal design tokens.
///
/// Surface/text tokens are palette-driven (see [AppPalette]); semantic accents
/// are shared across themes. Deliberately restrained: hairline borders instead
/// of shadows, tabular numerals for anything numeric, and colour reserved for
/// direction (P&L, bids/asks).
class AppColors {
  const AppColors._();

  static AppPalette _palette = AppPalette.dark;

  /// Switches the active palette. Callers must rebuild afterwards.
  static void use(AppPalette palette) => _palette = palette;

  static AppPalette get palette => _palette;

  // ---- Surface + text (theme-dependent) ----
  static Color get carbon => _palette.carbon;
  static Color get panelDark => _palette.panel;
  static Color get raisedDark => _palette.raised;
  static Color get hairlineDark => _palette.hairline;
  static Color get textPrimaryDark => _palette.textPrimary;
  static Color get textSecondaryDark => _palette.textSecondary;
  static Color get textMutedDark => _palette.textMuted;
  static Color get neutral => _palette.neutral;

  // ---- Semantic accents (identical in both themes) ----

  /// Muted emerald — strictly positive P&L and bids.
  static const Color positive = Color(0xFF10B981);

  /// Muted crimson — strictly negative P&L and asks.
  static const Color negative = Color(0xFFEF4444);

  /// Amber — offline / queued sync state.
  static const Color warning = Color(0xFFD97706);

  /// Focus ring for keyboard-first navigation.
  static const Color focus = Color(0xFF3B82F6);
}

/// 4px-based spacing scale. Kept tight for high-density layouts.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Institutional terminals stay nearly square.
class AppRadii {
  const AppRadii._();

  static const double none = 0;
  static const double sm = 2;
  static const double md = 4;
  static const double lg = 6;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Border widths. Only hairlines are used structurally.
class AppBorders {
  const AppBorders._();

  static const double hairline = 1.0;
}

/// Typography: Inter for UI/labels, JetBrains Mono (tabular) for anything numeric.
class AppTypography {
  const AppTypography._();

  static const String uiFamily = 'Inter';
  static const String monoFamily = 'JetBrainsMono';

  /// Strict tabular figures so digits align and never jitter on live ticks.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// UI / label text (Inter).
  static TextStyle ui({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: uiFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Prices, tickers and quantities (JetBrains Mono, tabular).
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabularFigures,
    );
  }

  /// Small uppercase column headers / labels.
  static TextStyle label(Color? color) => ui(
        size: 11,
        weight: FontWeight.w600,
        color: color,
        letterSpacing: 0.6,
        height: 1.1,
      );
}
