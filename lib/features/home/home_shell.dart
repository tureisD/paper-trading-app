import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_database.dart';
import '../../data/ledger_repository.dart';
import '../../design/tokens.dart';
import '../../analytics/equity_snapshot_repository.dart';
import '../../market/instrument_repository.dart';
import '../../market/live_quotes.dart';
import '../../market/market_data_service.dart';
import '../../market/quote_repository.dart';
import '../../sync/sync_engine.dart';
import '../../trading/trading_engine.dart';
import '../discovery/discovery_tab.dart';
import '../portfolio/portfolio_tab.dart';
import '../sync/sync_dialog.dart';

/// Virtual cash added by the "DEPOSIT CASH" action.
const double kDepositAmount = 100000.0;

/// Minimum width for the split-pane layouts (Windows); narrower widths (Android)
/// fall back to stacked / modal presentation.
const double kSplitPaneMinWidth = 900;

/// The application frame: dense top bar, two-tab body, bottom segmented nav
/// (thumb-first on Android, `Ctrl+1`/`Ctrl+2` on Windows).
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.database,
    required this.databasePath,
    required this.ledger,
    required this.instruments,
    required this.quotes,
    required this.marketData,
    required this.engine,
    required this.syncEngine,
    required this.snapshots,
  });

  final AppDatabase database;
  final String databasePath;
  final LedgerRepository ledger;
  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final MarketDataService marketData;
  final TradingEngine engine;
  final SyncEngine syncEngine;
  final EquitySnapshotRepository snapshots;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  final GlobalKey<DiscoveryTabState> _discoveryKey =
      GlobalKey<DiscoveryTabState>();

  SyncOutcome? _syncOutcome;
  late final LiveQuoteService _liveQuotes;

  @override
  void initState() {
    super.initState();
    _liveQuotes = LiveQuoteService(
      quotes: widget.quotes,
      engine: widget.engine,
    );
    _syncOutcome = widget.syncEngine.lastOutcome;
    // Silent background pull/push when a vault is already configured.
    if (widget.syncEngine.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncNow());
    }
  }

  @override
  void dispose() {
    _liveQuotes.dispose();
    widget.syncEngine.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  void _deposit() {
    widget.ledger.append(widget.ledger.deposit(amount: kDepositAmount));
    setState(() {});
  }

  Future<void> _syncNow() async {
    final outcome = await widget.syncEngine.syncNow();
    if (!mounted) return;
    setState(() => _syncOutcome = outcome);
  }

  Future<void> _openSyncDialog() async {
    await showSyncDialog(
      context,
      engine: widget.syncEngine,
      onChanged: () {
        if (mounted) {
          setState(() => _syncOutcome = widget.syncEngine.lastOutcome);
        }
      },
    );
    if (mounted) {
      setState(() => _syncOutcome = widget.syncEngine.lastOutcome);
    }
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
    if (ctrl && key == LogicalKeyboardKey.keyR) {
      if (_tab == 1) {
        _discoveryKey.currentState?.refreshQuotes();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // `/` jumps straight to search, per the roadmap keymap.
    if (!ctrl && key == LogicalKeyboardKey.slash) {
      _selectTab(1);
      _discoveryKey.currentState?.focusSearch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      FocusManager.instance.primaryFocus?.unfocus();
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
              pendingSync: widget.ledger.pendingCount(),
              syncOutcome: _syncOutcome,
              onSyncTap: _openSyncDialog,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  PortfolioTab(
                    databasePath: widget.databasePath,
                    ledger: widget.ledger,
                    instruments: widget.instruments,
                    quotes: widget.quotes,
                    marketData: widget.marketData,
                    engine: widget.engine,
                    snapshots: widget.snapshots,
                    syncEngine: widget.syncEngine,
                    liveQuotes: _liveQuotes,
                    syncOutcome: _syncOutcome,
                    pendingSync: widget.ledger.pendingCount(),
                    onOpenSync: _openSyncDialog,
                    onSyncNow: _syncNow,
                    onDeposit: _deposit,
                  ),
                  DiscoveryTab(
                    key: _discoveryKey,
                    instruments: widget.instruments,
                    quotes: widget.quotes,
                    marketData: widget.marketData,
                    engine: widget.engine,
                    liveQuotes: _liveQuotes,
                    onTraded: () => setState(() {}),
                  ),
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
    required this.pendingSync,
    required this.syncOutcome,
    required this.onSyncTap,
  });

  final String journalMode;
  final int schemaVersion;
  final int pendingSync;
  final SyncOutcome? syncOutcome;
  final VoidCallback onSyncTap;

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
          if (MediaQuery.sizeOf(context).width >= 900) ...[
            const SizedBox(width: AppSpacing.lg),
            Text(
              'Ctrl+1/2  •  /  •  Ctrl+R',
              style: AppTypography.mono(
                size: 10,
                color: AppColors.textMutedDark,
              ),
            ),
          ],
          const Spacer(),
          _StatusPill(
            pending: pendingSync,
            outcome: syncOutcome,
            onTap: onSyncTap,
          ),
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
  const _StatusPill({
    required this.pending,
    required this.outcome,
    required this.onTap,
  });

  final int pending;
  final SyncOutcome? outcome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = outcome?.state;
    late final String label;
    late final Color colour;

    switch (state) {
      case SyncState.synced:
        label = outcome!.label;
        colour = AppColors.positive;
      case SyncState.syncing:
        label = 'SYNCING…';
        colour = AppColors.focus;
      case SyncState.error:
        label = 'SYNC ERROR • QUEUED ($pending)';
        colour = AppColors.negative;
      case SyncState.offline:
        label = 'OFFLINE • QUEUED ($pending)';
        colour = AppColors.warning;
      case SyncState.notConfigured:
      case null:
        label = 'LOCAL • QUEUED ($pending)';
        colour = AppColors.warning;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.mono(
                size: 11,
                weight: FontWeight.w600,
                color: AppColors.textSecondaryDark,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
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
