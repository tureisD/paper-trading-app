import 'package:flutter/material.dart';

/// Layout breakpoints. The app is phone-first on Android and split-pane on
/// desktop, so every screen has a compact and an expanded presentation.
class Breakpoints {
  const Breakpoints._();

  /// Phones in portrait. Below this, tables become cards and the top bar trims.
  static const double compact = 700;

  /// Enough width for master/detail side by side.
  static const double wide = 900;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// Shared page padding: tight on phones, roomy on desktop.
class PagePadding {
  const PagePadding._();

  static EdgeInsets of(BuildContext context, {double? top}) {
    final compact = Breakpoints.isCompact(context);
    final horizontal = compact ? 12.0 : 16.0;
    return EdgeInsets.fromLTRB(horizontal, top ?? horizontal, horizontal, horizontal);
  }
}

/// A responsive dialog shell: full width minus a margin on phones, fixed width
/// on desktop, always inside the safe area.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.maxHeight = 680,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewInsetsOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: (size.height - inset.vertical - 48).clamp(240.0, maxHeight),
        ),
        child: child,
      ),
    );
  }
}
