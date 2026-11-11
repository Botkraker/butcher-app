import 'package:app/db.dart';
import 'package:app/native.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory settings, standing in for Android SharedPreferences.
class FakeNative implements Native {
  final data = <String, Object?>{};
  String? nextSpeech;
  int speechCalls = 0;

  @override
  Future<String?> speech() async {
    speechCalls++;
    return nextSpeech;
  }

  @override
  Future<int> firstInstallTime() async => DateTime.now().millisecondsSinceEpoch;
  @override
  Future<String?> getString(String file, String key) async => data['$file/$key'] as String?;
  @override
  Future<int?> getLong(String file, String key) async => data['$file/$key'] as int?;
  @override
  Future<bool?> getBool(String file, String key) async => data['$file/$key'] as bool?;
  @override
  Future<void> putString(String file, String key, String v) async => data['$file/$key'] = v;
  @override
  Future<void> putLong(String file, String key, int v) async => data['$file/$key'] = v;
  @override
  Future<void> putBool(String file, String key, bool v) async => data['$file/$key'] = v;
}

/// The v1 schema as the Kotlin app's Room created it, with Room's own bookkeeping table.
const roomV1 = [
  'CREATE TABLE IF NOT EXISTS `product_events` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `name` TEXT NOT NULL, `kind` TEXT NOT NULL, `pricePerKg` REAL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `supplier_events` (`uuid` TEXT NOT NULL, `supplierUuid` TEXT NOT NULL, `name` TEXT NOT NULL, `kind` TEXT NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `sales` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `total` REAL NOT NULL, `pricePerKg` REAL NOT NULL, `kg` REAL NOT NULL, `kind` TEXT NOT NULL, `credit` INTEGER NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `voids` (`uuid` TEXT NOT NULL, `targetTable` TEXT NOT NULL, `targetUuid` TEXT NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `carcasses` (`uuid` TEXT NOT NULL, `supplierUuid` TEXT, `kgBought` REAL NOT NULL, `cost` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `waste` (`uuid` TEXT NOT NULL, `carcassUuid` TEXT NOT NULL, `kg` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `closings` (`uuid` TEXT NOT NULL, `cashCounted` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `cash_moves` (`uuid` TEXT NOT NULL, `amount` REAL NOT NULL, `reason` TEXT NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS `stock_counts` (`uuid` TEXT NOT NULL, `productUuid` TEXT NOT NULL, `kg` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))',
  'CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)',
  "INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, 'abc')",
];

/// A fresh database in memory, made the way the app makes it.
Future<Database> memDb(DatabaseFactory f) => openButcherDb(f, inMemoryDatabasePath);
