import 'package:sqlite3/sqlite3.dart';

import '../core/ids.dart';
import '../data/app_database.dart';

/// A paper portfolio.
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

/// Create / list / rename / remove portfolios.
class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  static const String defaultAccountId = 'default';

  /// Returns the default portfolio, creating it on first use.
  Account ensureDefault() {
    final existing = get(defaultAccountId);
    if (existing != null) return existing;
    _insert(defaultAccountId, 'Default portfolio');
    return get(defaultAccountId)!;
  }

  Account? get(String accountId) {
    final rows = _db.raw
        .select('SELECT * FROM accounts WHERE account_id = ?;', [accountId]);
    return rows.isEmpty ? null : Account.fromRow(rows.first);
  }

  /// Every portfolio, oldest first.
  List<Account> all() {
    final rows =
        _db.raw.select('SELECT * FROM accounts ORDER BY created_at, name;');
    return rows.map(Account.fromRow).toList(growable: false);
  }

  /// Creates a portfolio with a custom name. Returns null for a blank name.
  Account? create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final id = Ids.uuidV7();
    _insert(id, trimmed);
    return get(id);
  }

  void rename(String accountId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _db.raw.execute(
      'UPDATE accounts SET name = ? WHERE account_id = ?;',
      [trimmed, accountId],
    );
  }

  /// Removes the portfolio row. The caller purges its ledger data.
  void delete(String accountId) {
    if (accountId == defaultAccountId) return;
    _db.raw.execute('DELETE FROM accounts WHERE account_id = ?;', [accountId]);
  }

  void _insert(String accountId, String name) {
    _db.raw.execute(
      'INSERT INTO accounts(account_id, name, base_currency, created_at) '
      'VALUES(?, ?, ?, ?);',
      [accountId, name, 'USD', DateTime.now().toUtc().toIso8601String()],
    );
  }
}
