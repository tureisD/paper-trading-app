import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/ledger_repository.dart';
import '../../data/settings_store.dart';
import '../../design/layout.dart';
import '../../design/theme_controller.dart';
import '../../design/tokens.dart';
import '../../trading/account_repository.dart';

/// Portfolio + app settings: appearance, portfolios, funding and withdrawals.
Future<void> showSettingsDialog(
  BuildContext context, {
  required SettingsStore settings,
  required ThemeController theme,
  required LedgerRepository ledger,
  required AccountRepository accounts,
  required String accountId,
  required String accountName,
  required ValueChanged<String> onAccountChanged,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => AppDialog(
      maxWidth: 560,
      child: _SettingsDialog(
        settings: settings,
        theme: theme,
        ledger: ledger,
        accounts: accounts,
        accountId: accountId,
        accountName: accountName,
        onAccountChanged: onAccountChanged,
        onChanged: onChanged,
      ),
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.theme,
    required this.ledger,
    required this.accounts,
    required this.accountId,
    required this.accountName,
    required this.onAccountChanged,
    required this.onChanged,
  });

  final SettingsStore settings;
  final ThemeController theme;
  final LedgerRepository ledger;
  final AccountRepository accounts;
  final String accountId;
  final String accountName;
  final ValueChanged<String> onAccountChanged;
  final VoidCallback onChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _funds =
      TextEditingController(text: widget.settings.depositAmount.toStringAsFixed(0));
  final TextEditingController _withdraw = TextEditingController();
  final TextEditingController _newPortfolio = TextEditingController();
  final TextEditingController _rename = TextEditingController();

  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _rename.text = widget.accountName;
  }

  @override
  void dispose() {
    _funds.dispose();
    _withdraw.dispose();
    _newPortfolio.dispose();
    _rename.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', ''));

  double get _cash => widget.ledger.cashBalance(accountId: widget.accountId);

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  // ---- funds ----

  void _addFunds() {
    final value = _parse(_funds);
    if (value == null || value <= 0) return _say('Enter a positive amount', error: true);
    widget.settings.depositAmount = value;
    widget.ledger.append(
      widget.ledger.deposit(amount: value, accountId: widget.accountId),
    );
    widget.onChanged();
    _say('Added ${formatMoney(value)} • cash ${formatMoney(_cash)}');
  }

  void _withdrawAmount({required bool everything}) {
    final cash = _cash;
    final value = everything ? cash : _parse(_withdraw);
    if (value == null || value <= 0) {
      return _say('Enter a positive amount to remove', error: true);
    }
    if (value > cash + 1e-9) {
      return _say('Cannot remove more than the ${formatMoney(cash)} balance', error: true);
    }
    widget.ledger.append(
      widget.ledger.withdrawal(amount: value, accountId: widget.accountId),
    );
    widget.onChanged();
    _say('Removed ${formatMoney(value)} • cash ${formatMoney(_cash)}');
  }

  // ---- portfolios ----

  void _createPortfolio() {
    final account = widget.accounts.create(_newPortfolio.text);
    if (account == null) return _say('Enter a portfolio name', error: true);
    widget.ledger.append(
      widget.ledger.deposit(
        amount: widget.settings.depositAmount,
        accountId: account.accountId,
      ),
    );
    Navigator.of(context).pop();
    widget.onAccountChanged(account.accountId);
  }

  void _renamePortfolio() {
    if (_rename.text.trim().isEmpty) {
      return _say('Enter a portfolio name', error: true);
    }
    widget.accounts.rename(widget.accountId, _rename.text);
    widget.onChanged();
    _say('Renamed to "${_rename.text.trim()}"');
  }

  Future<void> _deletePortfolio() async {
    if (widget.accountId == AccountRepository.defaultAccountId) {
      return _say('The default portfolio cannot be removed', error: true);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panelDark,
        title: Text(
          'Remove "${widget.accountName}"?',
          style: AppTypography.ui(size: 14, color: AppColors.textPrimaryDark),
        ),
        content: Text(
          'Its trades, positions and history are deleted from this device. '
          'If the portfolio has already synced, another linked device will '
          'upload it again.',
          style: AppTypography.ui(
            size: 12,
            color: AppColors.textSecondaryDark,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('REMOVE', style: TextStyle(color: AppColors.negative)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    widget.ledger.purgeAccount(widget.accountId);
    widget.accounts.delete(widget.accountId);
    if (mounted) Navigator.of(context).pop();
    widget.onAccountChanged(AccountRepository.defaultAccountId);
  }

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    final portfolios = widget.accounts.all();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 660),
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
            _header(hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _appearance(),
                    _divider(hairline),
                    _portfolios(portfolios),
                    _divider(hairline),
                    _fundsSection(),
                    _divider(hairline),
                    _withdrawSection(),
                  ],
                ),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  _message!,
                  style: AppTypography.mono(
                    size: 11,
                    color: _messageIsError
                        ? AppColors.negative
                        : AppColors.positive,
                  ),
                ),
              ),
            _footer(hairline),
          ],
        ),
      ),
    );
  }

  Widget _header(Color hairline) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.raisedDark,
          border: Border(
            bottom: BorderSide(color: hairline, width: AppBorders.hairline),
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
              'CASH ${formatMoney(_cash)}',
              style: AppTypography.mono(
                size: 10,
                color: AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      );

  Widget _divider(Color hairline) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Container(height: AppBorders.hairline, color: hairline),
      );

  Widget _sectionTitle(String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.label(AppColors.textMutedDark)),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  hint,
                  style: AppTypography.ui(
                    size: 11,
                    color: AppColors.textMutedDark,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _appearance() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('APPEARANCE'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: widget.theme,
          builder: (context, mode, _) => Row(
            children: [
              _pill('DARK', mode == ThemeMode.dark, () {
                widget.theme.select(ThemeMode.dark);
                setState(() {});
              }),
              const SizedBox(width: AppSpacing.sm),
              _pill('LIGHT', mode == ThemeMode.light, () {
                widget.theme.select(ThemeMode.light);
                setState(() {});
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _portfolios(List<Account> portfolios) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'PORTFOLIOS',
          'Each portfolio has its own cash, holdings and history. All of them '
          'sync together.',
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final portfolio in portfolios)
              _pill(
                '${portfolio.name}'
                '${portfolio.accountId == widget.accountId ? '  ●' : ''}',
                portfolio.accountId == widget.accountId,
                portfolio.accountId == widget.accountId
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        widget.onAccountChanged(portfolio.accountId);
                      },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _field(_newPortfolio, hint: 'New portfolio name'),
            ),
            const SizedBox(width: AppSpacing.sm),
            _action('CREATE', AppColors.focus, _createPortfolio),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _field(_rename, hint: 'Rename current')),
            const SizedBox(width: AppSpacing.sm),
            _action('RENAME', AppColors.textSecondaryDark, _renamePortfolio),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _action('REMOVE CURRENT', AppColors.negative, () {
            _deletePortfolio();
          }),
        ),
      ],
    );
  }

  Widget _fundsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'ADD FUNDS',
          'Simulated cash credited as a ledger deposit.',
        ),
        Row(
          children: [
            Expanded(
              child: _field(_funds, hint: '0', suffix: 'USD'),
            ),
            const SizedBox(width: AppSpacing.sm),
            _action('ADD FUNDS', AppColors.positive, _addFunds),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final preset in SettingsStore.depositPresets)
              _pill(
                formatMoney(preset),
                false,
                () => setState(() => _funds.text = preset.toStringAsFixed(0)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _withdrawSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'REMOVE FUNDS',
          'Withdraw simulated cash. Removals are recorded in the ledger, so '
          'they sync and remain visible in the history.',
        ),
        Row(
          children: [
            Expanded(child: _field(_withdraw, hint: '0', suffix: 'USD')),
            const SizedBox(width: AppSpacing.sm),
            _action(
              'REMOVE',
              AppColors.warning,
              () => _withdrawAmount(everything: false),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: _action(
            'CLEAR ALL CASH',
            AppColors.negative,
            () => _withdrawAmount(everything: true),
          ),
        ),
      ],
    );
  }

  Widget _footer(Color hairline) => Container(
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
          ],
        ),
      );

  Widget _field(
    TextEditingController controller, {
    String? hint,
    String? suffix,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
              controller: controller,
              style: AppTypography.mono(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
              cursorColor: AppColors.focus,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppTypography.ui(
                  size: 12,
                  color: AppColors.textMutedDark,
                ),
              ),
            ),
          ),
          if (suffix != null)
            Text(
              suffix,
              style: AppTypography.mono(
                size: 10,
                color: AppColors.textMutedDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String label, bool active, VoidCallback? onTap) {
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
          label.toUpperCase(),
          style: AppTypography.mono(
            size: 11,
            weight: FontWeight.w600,
            letterSpacing: 0.4,
            color: active ? AppColors.textPrimaryDark : AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }

  Widget _action(String label, Color accent, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: _buttonStyle(accent),
        child: Text(label),
      );

  ButtonStyle _buttonStyle(Color accent) => TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        foregroundColor: accent,
        textStyle: AppTypography.mono(
          size: 11,
          weight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
}
