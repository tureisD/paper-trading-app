import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/app.dart';
import 'package:paper_trading_app/data/app_database.dart';

void main() {
  testWidgets('renders the engine status and derives cash from a deposit',
      (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    await tester.pumpWidget(
      PaperTradingApp(database: db, databasePath: ':memory:'),
    );

    expect(find.text('TUREIS'), findsOneWidget);
    expect(find.text('LOCAL ENGINE'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);

    await tester.tap(find.text('RUN SMOKE TEST'));
    await tester.pump();

    expect(find.text(r'$100,000.00'), findsOneWidget);
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
}
