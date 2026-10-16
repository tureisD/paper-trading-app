import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the Material [ThemeData] from the design tokens.
///
/// Both themes share geometry (hairlines, tight radii, no elevation) and differ
/// only in surface/text colours.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: AppColors.carbon,
        surface: AppColors.panelDark,
        hairline: AppColors.hairlineDark,
        textPrimary: AppColors.textPrimaryDark,
        textSecondary: AppColors.textSecondaryDark,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: AppColors.paper,
        surface: AppColors.panelLight,
        hairline: AppColors.hairlineLight,
        textPrimary: AppColors.textPrimaryLight,
        textSecondary: AppColors.textSecondaryLight,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color hairline,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.focus,
      brightness: brightness,
    ).copyWith(
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: hairline,
      error: AppColors.negative,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: AppTypography.uiFamily,
      dividerColor: hairline,
      // No ink splashes / ripples: brutalist terminal feel.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );

    return base.copyWith(
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: AppBorders.hairline,
        space: AppBorders.hairline,
      ),
      iconTheme: IconThemeData(color: textSecondary, size: 16),
      textTheme: base.textTheme.apply(
        fontFamily: AppTypography.uiFamily,
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.raisedDark,
          border: Border.all(color: hairline, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        textStyle: AppTypography.ui(size: 11, color: textPrimary),
      ),
    );
  }
}
