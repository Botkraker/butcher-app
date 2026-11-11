import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The same file and the same tables as the Kotlin app (Room), so an update keeps the butcher's data.
/// Room set PRAGMA user_version to 1 or 2. sqflite reads the same number.
const dbName = 'butcher.db';
const dbVersion = 2;

// Exactly what Room created for the v1 entities.
const _v1 = [
  'CREATE TABLE IF NOT EXISTS `product_events` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `name` TEXT NOT NULL, '
      '`kind` TEXT NOT NULL, `pricePerKg` REAL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `supplier_events` (`uuid` TEXT NOT NULL, `supplierUuid` TEXT NOT NULL, `name` TEXT NOT NULL, '
      '`kind` TEXT NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `sales` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `total` REAL NOT NULL, '
      '`pricePerKg` REAL NOT NULL, `kg` REAL NOT NULL, `kind` TEXT NOT NULL, `credit` INTEGER NOT NULL, '
      '`deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `voids` (`uuid` TEXT NOT NULL, `targetTable` TEXT NOT NULL, `targetUuid` TEXT NOT NULL, '
      '`deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `carcasses` (`uuid` TEXT NOT NULL, `supplierUuid` TEXT, `kgBought` REAL NOT NULL, '
      '`cost` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `waste` (`uuid` TEXT NOT NULL, `carcassUuid` TEXT NOT NULL, `kg` REAL NOT NULL, '
      '`deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `closings` (`uuid` TEXT NOT NULL, `cashCounted` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, '
      '`synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `cash_moves` (`uuid` TEXT NOT NULL, `amount` REAL NOT NULL, `reason` TEXT NOT NULL, '
      '`deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `stock_counts` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `kg` REAL NOT NULL, '
      '`deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
];

// v1 -> v2: two new tables, nothing old changes (same SQL as the Kotlin MIGRATION_1_2).
const _v2 = [
  'CREATE TABLE IF NOT EXISTS `credit_events` (`uuid` TEXT NOT NULL, `person` TEXT NOT NULL, '
      '`amount` REAL NOT NULL, `kind` TEXT NOT NULL, `saleUuid` TEXT, `deviceTime` INTEGER NOT NULL, '
      '`synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `purchases` (`uuid` TEXT NOT NULL, `item` TEXT NOT NULL, `kg` REAL NOT NULL, '
      '`pricePerKg` REAL NOT NULL, `cost` REAL NOT NULL, `paid` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, '
      '`synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
];

/// Opens or creates the database. Never deletes data: an unknown newer version stops with an error.
Future<Database> openButcherDb(DatabaseFactory factory, String path) => factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onCreate: (db, _) async {
          for (final s in [..._v1, ..._v2]) {
            await db.execute(s);
          }
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) {
            for (final s in _v2) {
              await db.execute(s);
            }
          }
        },
      ),
    );

/// The queries of the Kotlin AppDao, one for one. Inserts only; no update or delete of data rows.
class Dao {
  Dao(this.e);
  final DatabaseExecutor e;

  static const _liveSale = "uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'sales')";

  Future<void> insertProductEvent(ProductEvent r) => e.insert('product_events', r.toMap());
  Future<void> insertSale(Sale r) => e.insert('sales', r.toMap());
  Future<void> insertVoid(VoidRow r) => e.insert('voids', r.toMap());
  Future<void> insertCashMove(CashMove r) => e.insert('cash_moves', r.toMap());
  Future<void> insertCreditEvent(CreditEvent r) => e.insert('credit_events', r.toMap());
  Future<void> insertPurchase(Purchase r) => e.insert('purchases', r.toMap());

  Future<List<ProductEvent>> productEvents() async =>
      (await e.rawQuery('SELECT * FROM product_events ORDER BY deviceTime, rowid')).map(ProductEvent.fromMap).toList();

  Future<Sale?> lastLiveSale() async {
    final r = await e.rawQuery('SELECT * FROM sales WHERE $_liveSale ORDER BY deviceTime DESC, rowid DESC LIMIT 1');
    return r.isEmpty ? null : Sale.fromMap(r.first);
  }

  Future<List<Sale>> liveSales() async =>
      (await e.rawQuery('SELECT * FROM sales WHERE $_liveSale ORDER BY deviceTime DESC, rowid DESC LIMIT 500'))
          .map(Sale.fromMap)
          .toList();

  Future<List<Sale>> salesSince(int since) async =>
      (await e.rawQuery('SELECT * FROM sales WHERE deviceTime >= ? AND $_liveSale', [since])).map(Sale.fromMap).toList();

  Future<List<String>> voidedIds() async =>
      (await e.rawQuery('SELECT targetUuid FROM voids')).map((r) => r['targetUuid'] as String).toList();

  Future<List<CreditEvent>> creditEvents() async =>
      (await e.rawQuery('SELECT * FROM credit_events ORDER BY deviceTime DESC, rowid DESC')).map(CreditEvent.fromMap).toList();

  Future<CreditEvent?> creditForSale(String saleUuid) async {
    final r = await e.rawQuery(
        'SELECT * FROM credit_events WHERE saleUuid = ? AND uuid NOT IN (SELECT targetUuid FROM voids) LIMIT 1', [saleUuid]);
    return r.isEmpty ? null : CreditEvent.fromMap(r.first);
  }

  Future<List<Purchase>> livePurchases() async => (await e.rawQuery(
          "SELECT * FROM purchases WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'purchases') "
          'ORDER BY deviceTime DESC, rowid DESC'))
      .map(Purchase.fromMap)
      .toList();

  Future<List<CashMove>> liveCashMoves() async => (await e.rawQuery(
          "SELECT * FROM cash_moves WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'cash_moves') "
          'ORDER BY deviceTime DESC, rowid DESC'))
      .map(CashMove.fromMap)
      .toList();

  /// Unsent rows of one table, 100 at a time.
  Future<List<Map<String, Object?>>> unsent(String table) => e.rawQuery('SELECT * FROM $table WHERE synced = 0 LIMIT 100');

  /// Upload marker only.
  Future<void> mark(String table, List<String> ids) async {
    if (ids.isEmpty) return;
    final q = List.filled(ids.length, '?').join(',');
    await e.rawUpdate('UPDATE $table SET synced = 1 WHERE uuid IN ($q)', ids);
  }
}
