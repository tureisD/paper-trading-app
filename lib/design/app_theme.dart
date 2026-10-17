import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the Material [ThemeData] from the design tokens.
///
/// Surface/text colours come from the active [AppColors.palette], so the widget
/// layer only ever reads tokens and both appearances share the same geometry
/// (hairlines, tight radii, no elevation).
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        palette: AppPalette.dark,
        accent: AppColors.focus,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        palette: AppPalette.light,
        accent: AppColors.focus,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color accent,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      surface: palette.panel,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.hairline,
      error: AppColors.negative,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.carbon,
      fontFamily: AppTypography.uiFamily,
      dividerColor: palette.hairline,
      // No ink splashes / ripples: brutalist terminal feel.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
    );

    return base.copyWith(
      dividerTheme: DividerThemeData(
        color: palette.hairline,
        thickness: AppBorders.hairline,
        space: AppBorders.hairline,
      ),
      iconTheme: IconThemeData(color: palette.textSecondary, size: 16),
      textTheme: base.textTheme.apply(
        fontFamily: AppTypography.uiFamily,
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.raised,
          border: Border.all(
            color: palette.hairline,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        textStyle: AppTypography.ui(size: 11, color: palette.textPrimary),
      ),
    );
  }
}
