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
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('NO OPEN POSITIONS'), findsOneWidget);

    await tester.tap(find.text('DEPOSIT CASH'));
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
