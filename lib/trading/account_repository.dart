import 'package:sqlite3/sqlite3.dart';

import '../data/app_database.dart';

/// A paper trading account (single-user for now).
class Account {
  const Account({
    required this.accountId,
    required this.name,
    required this.baseCurrency,
    required this.createdAt,
  });

  final String accountId;
  final String name;
  final String baseCurrency;
  final DateTime createdAt;

  factory Account.fromRow(Row row) => Account(
        accountId: row['account_id'] as String,
        name: row['name'] as String,
        baseCurrency: row['base_currency'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  static const String defaultAccountId = 'default';

  /// Returns the default account, creating it on first use.
  Account ensureDefault() {
    final existing = get(defaultAccountId);
    if (existing != null) return existing;

    _db.raw.execute(
      'INSERT INTO accounts(account_id, name, base_currency, created_at) '
      'VALUES(?, ?, ?, ?);',
      [
        defaultAccountId,
        'Paper Account',
        'USD',
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return get(defaultAccountId)!;
  }

  Account? get(String accountId) {
    final rows = _db.raw
        .select('SELECT * FROM accounts WHERE account_id = ?;', [accountId]);
    return rows.isEmpty ? null : Account.fromRow(rows.first);
  }
}
