import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/app_database.dart';
import '../../data/ledger_repository.dart';
import '../../design/tokens.dart';

/// The application frame: a dense top bar, a two-tab body, and a bottom
/// segmented control (thumb-first on Android, `Ctrl+1`/`Ctrl+2` on Windows).
///
/// The tab bodies are intentionally placeholders in Phase 1 — Phases 5 and 6
/// fill them in. What is real here is the theme, the geometry, and a live read
/// of the local SQLite engine.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.database,
    required this.ledger,
    required this.databasePath,
  });

  final AppDatabase database;
  final LedgerRepository ledger;
  final String databasePath;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  int _ledgerCount = 0;
  int _pending = 0;
  double _cash = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _ledgerCount = widget.database.ledgerEventCount();
      _pending = widget.ledger.pendingCount();
      _cash = widget.ledger.cashBalance();
    });
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  void _runSmokeTest() {
    widget.ledger.append(widget.ledger.deposit(amount: 100000));
    _refresh();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && key == LogicalKeyboardKey.digit1) {
      _selectTab(0);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.digit2) {
      _selectTab(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _TopBar(
              journalMode: widget.database.journalMode,
              schemaVersion: widget.database.schemaVersion,
              pending: _pending,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _PortfolioTab(
                    databasePath: widget.databasePath,
                    journalMode: widget.database.journalMode,
                    schemaVersion: widget.database.schemaVersion,
                    ledgerCount: _ledgerCount,
                    pending: _pending,
                    cash: _cash,
                    instrumentCount: widget.database.instrumentCount(),
                    onRunSmokeTest: _runSmokeTest,
                  ),
                  const _DiscoveryTab(),
                ],
              ),
            ),
            _SegmentBar(index: _tab, onChanged: _selectTab),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.journalMode,
    required this.schemaVersion,
    required this.pending,
  });

  final String journalMode;
  final int schemaVersion;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hairline = Theme.of(context).dividerColor;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border(
          bottom: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const _TbMark(size: 22),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'TUREIS',
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w700,
              color: onSurface,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            'BANKING',
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w400,
              color: AppColors.neutral,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(width: AppBorders.hairline, height: 16, color: hairline),
          const SizedBox(width: AppSpacing.md),
          Text(
            'LEDGER v$schemaVersion  •  ${journalMode.toUpperCase()}',
            style: AppTypography.mono(
              size: 11,
              color: AppColors.textMutedDark,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          _StatusPill(pending: pending),
        ],
      ),
    );
  }
}

/// The brand mark: a miniature of the app icon, drawn with widgets so it stays
/// crisp at any DPI without a raster asset.
class _TbMark extends StatelessWidget {
  const _TbMark({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.carbon,
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.smAll,
      ),
      alignment: Alignment.center,
      child: Text(
        'TB',
        style: AppTypography.mono(
          size: size * 0.44,
          weight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: 0,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairlineDark, width: AppBorders.hairline),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'LOCAL • QUEUED ($pending)',
            style: AppTypography.mono(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textSecondaryDark,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Portfolio (placeholder + live engine read)
// ---------------------------------------------------------------------------

class _PortfolioTab extends StatelessWidget {
  const _PortfolioTab({
    required this.databasePath,
    required this.journalMode,
    required this.schemaVersion,
    required this.ledgerCount,
    required this.pending,
    required this.cash,
    required this.instrumentCount,
    required this.onRunSmokeTest,
  });

  final String databasePath;
  final String journalMode;
  final int schemaVersion;
  final int ledgerCount;
  final int pending;
  final double cash;
  final int instrumentCount;
  final VoidCallback onRunSmokeTest;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            title: 'LOCAL ENGINE',
            trailing: _GhostButton(
              label: 'RUN SMOKE TEST',
              onPressed: onRunSmokeTest,
            ),
            child: Column(
              children: [
                _KeyValueRow(label: 'DATABASE', value: databasePath, mono: true),
                _KeyValueRow(label: 'JOURNAL', value: journalMode.toUpperCase(), mono: true),
                _KeyValueRow(label: 'SCHEMA', value: 'v$schemaVersion', mono: true),
                _KeyValueRow(label: 'LEDGER EVENTS', value: '$ledgerCount', mono: true),
                _KeyValueRow(label: 'QUEUED FOR SYNC', value: '$pending', mono: true),
                _KeyValueRow(label: 'INSTRUMENTS (FTS5)', value: '$instrumentCount', mono: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Panel(
            title: 'DERIVED STATE',
            child: Column(
              children: [
                _KeyValueRow(
                  label: 'CASH BALANCE',
                  value: formatMoney(cash),
                  mono: true,
                  emphasis: true,
                  valueColor: cash > 0 ? AppColors.positive : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Portfolio state is never stored — it is replayed from the '
                    'append-only ledger on every read.',
                    style: AppTypography.ui(
                      size: 12,
                      color: AppColors.textMutedDark,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Placeholder(
            title: 'HOLDINGS & P&L',
            body: 'High-density holdings table, equity curve and risk metrics '
                'arrive in Phase 5.',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Discovery (placeholder)
// ---------------------------------------------------------------------------

class _DiscoveryTab extends StatelessWidget {
  const _DiscoveryTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
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
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.search, size: 15, color: AppColors.textMutedDark),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Search ticker, pair, issuer or ISIN  (/)',
                  style: AppTypography.ui(
                    size: 12,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Placeholder(
            title: 'MULTI-ASSET DISCOVERY',
            body: 'Categorised instant search and the order ticket arrive in '
                'Phase 6.',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

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
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
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
    final base = mono
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
          Expanded(
            child: Text(
              value,
              style: base,
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 22),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.textSecondaryDark,
        shape: RoundedRectangleBorder(
          side: const BorderSide(
            color: AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.label(AppColors.textMutedDark)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTypography.ui(
              size: 12,
              color: AppColors.textMutedDark,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom segmented navigation
// ---------------------------------------------------------------------------

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border(
          top: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Row(
        children: [
          _Segment(
            index: 0,
            selected: index == 0,
            title: 'PORTFOLIO',
            hint: 'Ctrl+1',
            onTap: onChanged,
          ),
          _Segment(
            index: 1,
            selected: index == 1,
            title: 'DISCOVERY',
            hint: 'Ctrl+2',
            onTap: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.index,
    required this.selected,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final String title;
  final String hint;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.raisedDark : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: selected ? AppColors.focus : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: AppTypography.mono(
                  size: 11,
                  weight: FontWeight.w600,
                  color: selected
                      ? AppColors.textSecondaryDark
                      : AppColors.textMutedDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: selected
                      ? AppColors.textPrimaryDark
                      : AppColors.textMutedDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                hint,
                style: AppTypography.mono(
                  size: 10,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
