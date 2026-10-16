import 'package:flutter/widgets.dart';

/// Institutional trading-terminal design tokens.
///
/// Deliberately restrained: hairline borders instead of shadows, tabular
/// numerals for anything numeric, and semantic colour reserved for P&L only.
/// See roadmap section 1 ("Anti-Vibe-Code Specification").
class AppColors {
  const AppColors._();

  // ---- Dark surface (default) ----
  /// Matte carbon primary background.
  static const Color carbon = Color(0xFF0D0E11);

  /// Elevated panel background.
  static const Color panelDark = Color(0xFF13151A);

  /// Slightly raised row/header fill.
  static const Color raisedDark = Color(0xFF181B21);

  /// 1px structural hairline border.
  static const Color hairlineDark = Color(0xFF22252A);

  static const Color textPrimaryDark = Color(0xFFE6E8EB);
  static const Color textSecondaryDark = Color(0xFF9BA1A9);
  static const Color textMutedDark = Color(0xFF6B7178);

  // ---- Light surface ----
  /// Crisp paper primary background.
  static const Color paper = Color(0xFFF7F7F5);
  static const Color panelLight = Color(0xFFFFFFFF);
  static const Color raisedLight = Color(0xFFF1F2F0);
  static const Color hairlineLight = Color(0xFFE2E4E9);

  static const Color textPrimaryLight = Color(0xFF15171A);
  static const Color textSecondaryLight = Color(0xFF5A6069);
  static const Color textMutedLight = Color(0xFF8B929B);

  // ---- Semantic accents (P&L / bids / asks only) ----
  /// Muted emerald — strictly positive P&L and bids.
  static const Color positive = Color(0xFF10B981);

  /// Muted crimson — strictly negative P&L and asks.
  static const Color negative = Color(0xFFEF4444);

  /// Structural slate for chrome that must not imply direction.
  static const Color neutral = Color(0xFF8A9199);

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
