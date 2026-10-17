import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/ledger_repository.dart';
import '../../data/settings_store.dart';
import '../../design/theme_controller.dart';
import '../../design/tokens.dart';

/// Portfolio settings: UI theme and account funding.
Future<void> showSettingsDialog(
  BuildContext context, {
  required SettingsStore settings,
  required ThemeController theme,
  required LedgerRepository ledger,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => _SettingsDialog(
      settings: settings,
      theme: theme,
      ledger: ledger,
      onChanged: onChanged,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.theme,
    required this.ledger,
    required this.onChanged,
  });

  final SettingsStore settings;
  final ThemeController theme;
  final LedgerRepository ledger;
  final VoidCallback onChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.settings.depositAmount.toStringAsFixed(0));
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _addFunds() {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) {
      setState(() {
        _message = 'Enter a positive amount';
        _messageIsError = true;
      });
      return;
    }

    widget.settings.depositAmount = value;
    widget.ledger.append(widget.ledger.deposit(amount: value));
    widget.onChanged();
    setState(() {
      _message = 'Added ${formatMoney(value)} — cash balance '
          '${formatMoney(widget.ledger.cashBalance())}';
      _messageIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: AppColors.panelDark,
          border: Border.all(
            color: AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.mdAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.raisedDark,
                border: Border(
                  bottom:
                      BorderSide(color: hairline, width: AppBorders.hairline),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'SETTINGS',
                    style: AppTypography.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimaryDark,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'PAPER ACCOUNT',
                    style: AppTypography.mono(
                      size: 10,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'THEME',
                    style: AppTypography.label(AppColors.textMutedDark),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: widget.theme,
                    builder: (context, mode, _) => Row(
                      children: [
                        _themeChip('DARK', mode == ThemeMode.dark, () {
                          widget.theme.select(ThemeMode.dark);
                          setState(() {});
                        }),
                        const SizedBox(width: AppSpacing.sm),
                        _themeChip('LIGHT', mode == ThemeMode.light, () {
                          widget.theme.select(ThemeMode.light);
                          setState(() {});
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'ADD FUNDS',
                    style: AppTypography.label(AppColors.textMutedDark),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Simulated cash credited to the paper account as a ledger '
                    'deposit. Current balance '
                    '${formatMoney(widget.ledger.cashBalance())}.',
                    style: AppTypography.ui(
                      size: 11,
                      color: AppColors.textMutedDark,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    height: 36,
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.raisedDark,
                      border: Border.all(
                        color: AppColors.hairlineDark,
                        width: AppBorders.hairline,
                      ),
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            style: AppTypography.mono(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.textPrimaryDark,
                            ),
                            cursorColor: AppColors.focus,
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Text(
                          'USD',
                          style: AppTypography.mono(
                            size: 10,
                            color: AppColors.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final preset in SettingsStore.depositPresets)
                        _presetChip(preset),
                    ],
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _message!,
                      style: AppTypography.mono(
                        size: 11,
                        color: _messageIsError
                            ? AppColors.negative
                            : AppColors.positive,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: hairline, width: AppBorders.hairline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: _buttonStyle(AppColors.textSecondaryDark),
                      child: const Text('CLOSE'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextButton(
                      onPressed: _addFunds,
                      style: _buttonStyle(AppColors.positive),
                      child: const Text('ADD FUNDS'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.panelDark : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.focus : AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label,
          style: AppTypography.mono(
            size: 11,
            weight: FontWeight.w600,
            letterSpacing: 0.6,
            color: active ? AppColors.textPrimaryDark : AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }

  Widget _presetChip(double value) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(
        () => _amount.text = value.toStringAsFixed(0),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          formatMoney(value),
          style: AppTypography.mono(
            size: 10,
            color: AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle(Color accent) => TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        foregroundColor: accent,
        textStyle: AppTypography.mono(
          size: 11,
          weight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
}
