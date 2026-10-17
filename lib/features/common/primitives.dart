import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// A bordered panel with a hairline header bar.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border.all(color: hairline, width: AppBorders.hairline),
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.raisedDark,
              border: Border(
                bottom: BorderSide(color: hairline, width: AppBorders.hairline),
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTypography.label(AppColors.textSecondaryDark),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Label / value row used across the info panels.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? AppTypography.mono(
            size: emphasis ? 16 : 12,
            weight: emphasis ? FontWeight.w600 : FontWeight.w400,
            color: valueColor ?? AppColors.textPrimaryDark,
          )
        : AppTypography.ui(size: 12, color: AppColors.textPrimaryDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: AppTypography.label(AppColors.textMutedDark),
            ),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

/// Small bordered action button.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.accent,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colour = accent ?? AppColors.textSecondaryDark;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 22),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: colour,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colour, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        textStyle: AppTypography.mono(
          size: 10,
          weight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Centred muted placeholder text.
class EmptyLine extends StatelessWidget {
  const EmptyLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Text(
          text,
          style: AppTypography.mono(
            size: 11,
            color: AppColors.textMutedDark,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// A headline metric: small caption, large tabular value, optional sub-value.
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
    this.subColor,
    this.valueSize = 20,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final Color? subColor;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label(AppColors.textMutedDark)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.mono(
            size: valueSize,
            weight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimaryDark,
          ),
        ),
        if (sub != null)
          Text(
            sub!,
            style: AppTypography.mono(
              size: 11,
              color: subColor ?? AppColors.textMutedDark,
            ),
          ),
      ],
    );
  }
}
