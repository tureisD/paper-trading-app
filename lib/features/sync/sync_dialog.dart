import 'package:flutter/material.dart';

import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../sync/sync_coordinator.dart';
import '../../sync/sync_engine.dart';

/// Vault setup / manual sync dialog.
///
/// Returns true when a sync completed successfully, so the caller can refresh
/// derived views (remote events may have been merged).
Future<bool> showSyncDialog(
  BuildContext context, {
  required SyncCoordinator sync,
  required VoidCallback onChanged,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => _SyncDialog(sync: sync, onChanged: onChanged),
  );
  return result ?? false;
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.sync, required this.onChanged});

  final SyncCoordinator sync;
  final VoidCallback onChanged;

  SyncEngine get engine => sync.engine;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _gistId = TextEditingController();

  bool _busy = false;
  bool _dirty = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _gistId.text = widget.engine.config.gistId ?? '';
    if (widget.engine.config.token != null) {
      _token.text = widget.engine.config.token!;
    }
    _token.addListener(_markDirty);
    _gistId.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _token.removeListener(_markDirty);
    _gistId.removeListener(_markDirty);
    _token.dispose();
    _gistId.dispose();
    super.dispose();
  }

  Future<void> _run(Future<SyncOutcome?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final outcome = await action();
      if (!mounted) return;
      if (outcome == null) {
        setState(() {
          _messageIsError = true;
          _message = 'Connect a vault first.';
        });
        return;
      }
      setState(() {
        _messageIsError = !outcome.ok;
        _message = outcome.ok
            ? 'SYNC OK • pulled ${outcome.pulled} • pushed ${outcome.pushed}'
                '${outcome.latency == null ? '' : ' • ${outcome.latency!.inMilliseconds}ms'}'
            : (outcome.message ?? outcome.label);
      });
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() {
    final token = _token.text.trim();
    return _run(
      () => widget.engine.connect(
        token: token,
        gistId: _gistId.text.trim().isEmpty ? null : _gistId.text.trim(),
      ),
    );
  }

  Future<void> _syncNow() => _run(() => widget.sync.syncNow());

  void _disconnect() {
    widget.engine.disconnect();
    _token.clear();
    _gistId.clear();
    setState(() {
      _dirty = false;
      _message = 'Vault disconnected on this device.';
      _messageIsError = false;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.engine.config;
    final outcome = widget.engine.lastOutcome;
    final configured = widget.sync.isConfigured;

    return AppDialog(
      maxWidth: 520,
      child: Container(
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
            _header(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoRow('STATUS', outcome?.label ?? 'LOCAL ONLY'),
                  _infoRow(
                    'AUTO-SYNC',
                    configured
                        ? 'every ${widget.sync.pullInterval.inSeconds}s, plus '
                            'after each trade'
                        : 'not connected',
                  ),
                  _infoRow(
                    'DEVICE',
                    widget.engine.deviceId,
                  ),
                  _infoRow(
                    'ACCOUNT',
                    widget.engine.config.accountLogin ?? 'not verified',
                  ),
                  _infoRow(
                    'VAULT',
                    config.gistId ?? 'not connected',
                  ),
                  _infoRow(
                    'TOKEN STORAGE',
                    config.token == null
                        ? '—'
                        : (config.tokenEncrypted
                            ? 'WINDOWS DPAPI (encrypted)'
                            : 'PLAINTEXT (no OS keystore)'),
                  ),
                  _infoRow(
                    'PENDING EVENTS',
                    '${widget.engine.ledger.pendingCount()}',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _fieldLabel('GITHUB TOKEN'),
                  _input(_token, obscure: true, hint: 'github_pat_… or ghp_…'),
                  const SizedBox(height: AppSpacing.md),
                  _fieldLabel('GIST ID (LEAVE BLANK TO CREATE A NEW VAULT)'),
                  _input(_gistId, hint: 'e.g. 4ac33b9c00751fddc7f8'),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'The token needs the "gists" scope (classic) or the Gists '
                    'user permission (fine-grained). It is encrypted with '
                    'Windows DPAPI before being written to the local database, '
                    'and any pasted spaces or line breaks are stripped.',
                    style: AppTypography.ui(
                      size: 11,
                      color: AppColors.textMutedDark,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            _footer(configured),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final hairline = Theme.of(context).dividerColor;
    return Container(
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
            'GIST SYNC VAULT',
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.textPrimaryDark,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            widget.engine.deviceId.toUpperCase(),
            style: AppTypography.mono(
              size: 10,
              color: AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: AppTypography.label(AppColors.textMutedDark)),
      );

  Widget _input(
    TextEditingController controller, {
    bool obscure = false,
    String? hint,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.raisedDark,
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.smAll,
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: AppTypography.mono(
          size: 12,
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
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: AppTypography.label(AppColors.textMutedDark),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTypography.mono(
                  size: 11,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _footer(bool configured) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
          Row(
            children: [
              if (configured)
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : _disconnect,
                    style: _buttonStyle(AppColors.negative),
                    child: const Text('DISCONNECT'),
                  ),
                ),
              if (configured) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  style: _buttonStyle(AppColors.textSecondaryDark),
                  child: const Text('CLOSE'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: _busy ? null : _primaryAction(configured),
                  style: _buttonStyle(
                    _primaryAction(configured) == null
                        ? AppColors.textMutedDark
                        : AppColors.focus,
                  ),
                  child: Text(_primaryLabel(configured)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Once a vault is configured and the fields are untouched, the primary
  /// action is a plain sync; otherwise it sets the vault up.
  VoidCallback? _primaryAction(bool configured) {
    if (configured && !_dirty) return _syncNow;
    if (_token.text.trim().isEmpty) return null;
    return _connect;
  }

  String _primaryLabel(bool configured) {
    if (_busy) return 'WORKING…';
    if (configured && !_dirty) return 'SYNC NOW';
    if (_token.text.trim().isEmpty) return 'PASTE A TOKEN';
    return 'CONNECT & SYNC';
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
