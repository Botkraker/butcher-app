import 'package:flutter/services.dart';

/// Small key-value store. On the phone it is Android SharedPreferences, in the same files the
/// Kotlin app used ("butcher" and "seed"), so settings survive the move to Flutter.
abstract class Kv {
  Future<String?> getString(String file, String key);
  Future<int?> getLong(String file, String key);
  Future<bool?> getBool(String file, String key);
  Future<void> putString(String file, String key, String v);
  Future<void> putLong(String file, String key, int v);
  Future<void> putBool(String file, String key, bool v);
}

/// Phone-only features, behind one interface so tests can fake them.
abstract class Native implements Kv {
  /// Opens the phone's voice typing (ar-TN). Null when cancelled or when the phone has no voice app
  /// (the phone then shows a message itself).
  Future<String?> speech();
  Future<int> firstInstallTime();
}

class AndroidNative implements Native {
  static const _ch = MethodChannel('butcher/native');

  @override
  Future<String?> speech() => _ch.invokeMethod<String>('speech');
  @override
  Future<int> firstInstallTime() async => (await _ch.invokeMethod<int>('firstInstallTime')) ?? 0;
  @override
  Future<String?> getString(String file, String key) => _ch.invokeMethod<String>('getString', {'file': file, 'key': key});
  @override
  Future<int?> getLong(String file, String key) => _ch.invokeMethod<int>('getLong', {'file': file, 'key': key});
  @override
  Future<bool?> getBool(String file, String key) => _ch.invokeMethod<bool>('getBool', {'file': file, 'key': key});
  @override
  Future<void> putString(String file, String key, String v) =>
      _ch.invokeMethod('putString', {'file': file, 'key': key, 'value': v});
  @override
  Future<void> putLong(String file, String key, int v) => _ch.invokeMethod('putLong', {'file': file, 'key': key, 'value': v});
  @override
  Future<void> putBool(String file, String key, bool v) => _ch.invokeMethod('putBool', {'file': file, 'key': key, 'value': v});
}

/// The settings the Kotlin Prefs object kept, under the same names.
class Prefs {
  Prefs(this.kv);
  final Kv kv;

  Future<int> lastSync() async => await kv.getLong('butcher', 'last_sync') ?? 0;
  Future<void> setLastSync(int t) => kv.putLong('butcher', 'last_sync', t);

  /// Product order chosen by the butcher. Screen layout only, so it stays on the phone and is not synced.
  Future<List<String>> order() async =>
      (await kv.getString('butcher', 'product_order') ?? '').split(',').where((s) => s.isNotEmpty).toList();
  Future<void> setOrder(List<String> ids) => kv.putString('butcher', 'product_order', ids.join(','));

  /// Where the last read from Neon stopped, per table (uploaded_at in microseconds).
  Future<int> pullCursor(String table) async => await kv.getLong('butcher', 'pull_$table') ?? 0;
  Future<void> setPullCursor(String table, int us) => kv.putLong('butcher', 'pull_$table', us);

  Future<bool> seedDone() async => await kv.getBool('seed', 'done') ?? false;
  Future<void> setSeedDone() => kv.putBool('seed', 'done', true);
}
