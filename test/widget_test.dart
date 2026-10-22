import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/app.dart';
import 'package:paper_trading_app/data/app_database.dart';

void main() {
  testWidgets('renders the account panel and deposits paper cash',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(
      PaperTradingApp(database: db, databasePath: ':memory:'),
    );

    expect(find.text('TUREIS'), findsOneWidget);
    expect(find.text('ACCOUNT • DEFAULT PORTFOLIO'), findsOneWidget);
    expect(find.text('NO OPEN POSITIONS'), findsOneWidget);

    await tester.tap(find.text('DEPOSIT'));
    await tester.pump();

    // Cash now shows in both Net Liquidation Value and Buying Power.
    expect(find.text(r'$100,000.00'), findsWidgets);
    expect(find.text('ANALYTICS'), findsOneWidget);
    expect(find.text('HOLDINGS'), findsOneWidget);
  });

  testWidgets('switches tabs from the segmented control', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(
      PaperTradingApp(database: db, databasePath: ':memory:'),
    );

    await tester.tap(find.text('DISCOVERY'));
    await tester.pumpAndSettle();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
    expect(find.textContaining('Search ticker'), findsOneWidget);
  });

  testWidgets('reloads portfolio prices on command', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(
      PaperTradingApp(database: db, databasePath: ':memory:'),
    );
    await tester.pumpAndSettle();

    // The first paint already prices the book.
    expect(find.textContaining('PRICES UPDATED'), findsOneWidget);

    await tester.tap(find.text('RELOAD'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PRICES UPDATED'), findsOneWidget);
    expect(find.text('RELOAD'), findsOneWidget);
  });

  testWidgets('settings dialog exposes portfolios, funding and withdrawals',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(
      PaperTradingApp(database: db, databasePath: ':memory:'),
    );

    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.text('PORTFOLIOS'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('CLEAR ALL CASH'), findsOneWidget);
    expect(find.text('New portfolio name'), findsOneWidget);
    expect(find.text('Default portfolio'), findsWidgets);
  });
}
