import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'native.dart';

/// Set at build time: flutter run --dart-define-from-file=secrets.json (see README).
const neonSqlUrl = String.fromEnvironment('NEON_SQL_URL');
const neonConnectionString = String.fromEnvironment('NEON_CONNECTION_STRING');

/// Column types: u uuid, t epoch-ms time, r number, s text, b boolean.
/// [cols] maps a Neon column to the local (Room) column and its type.
class SyncTable {
  const SyncTable(this.name, this.cols);
  final String name;
  final List<(String neon, String local, String type)> cols;
}

const syncTables = [
  SyncTable('product_events', [
    ('uuid', 'uuid', 'u'), ('product_uuid', 'productUuid', 'u'), ('name', 'name', 's'), ('kind', 'kind', 's'),
    ('price_per_kg', 'pricePerKg', 'r'), ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('supplier_events', [
    ('uuid', 'uuid', 'u'), ('supplier_uuid', 'supplierUuid', 'u'), ('name', 'name', 's'), ('kind', 'kind', 's'),
    ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('sales', [
    ('uuid', 'uuid', 'u'), ('product_uuid', 'productUuid', 'u'), ('total', 'total', 'r'),
    ('price_per_kg', 'pricePerKg', 'r'), ('kg', 'kg', 'r'), ('kind', 'kind', 's'), ('credit', 'credit', 'b'),
    ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('voids', [
    ('uuid', 'uuid', 'u'), ('target_table', 'targetTable', 's'), ('target_uuid', 'targetUuid', 'u'),
    ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('carcasses', [
    ('uuid', 'uuid', 'u'), ('supplier_uuid', 'supplierUuid', 'u'), ('kg_bought', 'kgBought', 'r'), ('cost', 'cost', 'r'),
    ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('waste', [
    ('uuid', 'uuid', 'u'), ('carcass_uuid', 'carcassUuid', 'u'), ('kg', 'kg', 'r'), ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('closings', [('uuid', 'uuid', 'u'), ('cash_counted', 'cashCounted', 'r'), ('device_time', 'deviceTime', 't')]),
  SyncTable('cash_moves', [
    ('uuid', 'uuid', 'u'), ('amount', 'amount', 'r'), ('reason', 'reason', 's'), ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('stock_counts', [
    ('uuid', 'uuid', 'u'), ('product_uuid', 'productUuid', 'u'), ('kg', 'kg', 'r'), ('device_time', 'deviceTime', 't'),
  ]),
  // v2 tables last: if Neon misses them, the old tables still go up first.
  SyncTable('credit_events', [
    ('uuid', 'uuid', 'u'), ('person', 'person', 's'), ('amount', 'amount', 'r'), ('kind', 'kind', 's'),
    ('sale_uuid', 'saleUuid', 'u'), ('device_time', 'deviceTime', 't'),
  ]),
  SyncTable('purchases', [
    ('uuid', 'uuid', 'u'), ('item', 'item', 's'), ('kg', 'kg', 'r'), ('price_per_kg', 'pricePerKg', 'r'),
    ('cost', 'cost', 'r'), ('paid', 'paid', 'r'), ('device_time', 'deviceTime', 't'),
  ]),
];

String _cast(String t, int i) => switch (t) {
      'u' => '\$$i::uuid',
      't' => 'to_timestamp(\$$i::double precision / 1000)',
      'r' => '\$$i::double precision',
      'b' => '\$$i::boolean',
      _ => '\$$i::text',
    };

/// The value as Kotlin's toString() wrote it: 25.0, 1700000000000, true.
Object? _param(Object? v, String type) {
  if (v == null) return null;
  if (type == 'b') return (v == 1 || v == true).toString();
  if (type == 'r') return (v as num).toDouble().toString();
  return v.toString();
}

/// One statement: bare INSERT ... ON CONFLICT DO NOTHING (no target, no RETURNING).
Map<String, Object?> neonQuery(SyncTable t, Map<String, Object?> row, int sentAt) {
  final names = [...t.cols.map((c) => c.$1), 'sent_device_time'];
  final marks = [for (var i = 0; i < t.cols.length; i++) _cast(t.cols[i].$3, i + 1), _cast('t', t.cols.length + 1)];
  final params = [...t.cols.map((c) => _param(row[c.$2], c.$3)), sentAt.toString()];
  return {
    'query': 'INSERT INTO ${t.name} (${names.join(', ')}) VALUES (${marks.join(', ')}) ON CONFLICT DO NOTHING',
    'params': params,
  };
}

class Neon {
  Neon(this.client, {this.url = neonSqlUrl, this.conn = neonConnectionString});
  final http.Client client;
  final String url, conn;

  bool get configured => url.isNotEmpty;

  /// One read query. Returns HTTP code and body ({"rows": [{column: value}], ...}).
  Future<(int, String)> select(Map<String, Object?> query) async {
    final r = await client
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json', 'Neon-Connection-String': conn},
            body: jsonEncode(query))
        .timeout(const Duration(seconds: 45));
    return (r.statusCode, utf8.decode(r.bodyBytes)); // Neon sends UTF-8; the default would garble Arabic
  }

  /// Sends statements as one batch (one transaction). Returns HTTP code and body.
  Future<(int, String)> post(List<Map<String, Object?>> queries) async {
    final r = await client
        .post(Uri.parse(url),
            headers: {'Content-Type': 'application/json', 'Neon-Connection-String': conn},
            body: jsonEncode({'queries': queries}))
        .timeout(const Duration(seconds: 45));
    return (r.statusCode, utf8.decode(r.bodyBytes)); // Neon sends UTF-8; the default would garble Arabic
  }
}

/// Sends every unsent row. Returns null when all went up, else the error text. A failed table does not stop the others.
Future<String?> pushAll(Database db, Prefs prefs, Neon neon, {int Function()? clock}) async {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final dao = Dao(db);
  final errors = <String>[];
  try {
    for (final t in syncTables) {
      while (true) {
        final rows = await dao.unsent(t.name);
        if (rows.isEmpty) break;
        final sentAt = now();
        final qs = rows.map((r) => neonQuery(t, r, sentAt)).toList();
        final (code, body) = await neon.post(qs);
        if (code != 200) {
          errors.add('${t.name}: HTTP $code $body');
          break;
        }
        await dao.mark(t.name, rows.map((r) => r['uuid'] as String).toList());
        await prefs.setLastSync(now());
      }
    }
  } catch (e) {
    errors.add('${e.runtimeType}: $e');
  }
  return errors.isEmpty ? null : errors.join('\n');
}

/// Rows read per request. An upload batch is at most 100 rows with one uploaded_at, so a page always moves on.
const pullPage = 500;

String _sel(String col, String type) =>
    type == 't' ? '(extract(epoch from $col) * 1000)::bigint::text AS $col' : '$col::text AS $col';

/// Rows of one table that reached Neon at or after [cursorUs] (microseconds), oldest first. Every value as text.
Map<String, Object?> pullQuery(SyncTable t, int cursorUs) {
  final cols = [...t.cols.map((c) => _sel(c.$1, c.$3)), '(extract(epoch from uploaded_at) * 1000000)::bigint::text AS uploaded_us'];
  return {
    'query': 'SELECT ${cols.join(', ')} FROM ${t.name} '
        'WHERE uploaded_at >= to_timestamp(\$1::double precision / 1000000) ORDER BY uploaded_at, uuid LIMIT $pullPage',
    'params': [cursorUs.toString()],
  };
}

/// A Neon text value as the local (Room) column stores it.
Object? _local(Object? v, String type) {
  if (v == null) return null;
  final s = v.toString();
  return switch (type) {
    'r' => double.parse(s),
    't' => int.parse(s),
    'b' => s == 'true' || s == 't' ? 1 : 0,
    _ => s,
  };
}

/// Brings down every row the phone does not have yet (from another phone, or after a reinstall).
/// Rows are append-only with a UUID key, so a row the phone already has is skipped, never changed.
/// Returns null when every table was read, else the error text.
Future<String?> pullAll(Database db, Prefs prefs, Neon neon, {int Function()? clock}) async {
  final now = clock ?? () => DateTime.now().millisecondsSinceEpoch;
  final errors = <String>[];
  try {
    for (final t in syncTables) {
      var cursor = await prefs.pullCursor(t.name);
      while (true) {
        final (code, body) = await neon.select(pullQuery(t, cursor));
        if (code != 200) {
          errors.add('${t.name} (read): HTTP $code $body');
          break;
        }
        final rows = ((jsonDecode(body) as Map<String, dynamic>)['rows'] as List).cast<Map<String, dynamic>>();
        await db.transaction((txn) async {
          for (final r in rows) {
            await txn.insert(t.name, {for (final c in t.cols) c.$2: _local(r[c.$1], c.$3), 'synced': 1},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        });
        var next = cursor;
        for (final r in rows) {
          next = max(next, int.parse(r['uploaded_us'].toString()));
        }
        final done = rows.length < pullPage || next == cursor;
        cursor = next;
        await prefs.setPullCursor(t.name, cursor);
        if (done) break;
      }
    }
    if (errors.isEmpty) await prefs.setLastSync(now());
  } catch (e) {
    errors.add('read: ${e.runtimeType}: $e');
  }
  return errors.isEmpty ? null : errors.join('\n');
}

/// Wait before the next try after [fails] failed runs: 30 s, 1 min, 2 min, 4 min, then 5 min.
/// Short cap: there is no network signal, so a short wait is how the app notices the internet came back.
int retryDelay(int fails) => min(30 * (1 << min(fails, 10)), 300);

/// Replaces the Kotlin WorkManager job while the app is open: runs after every save and at start,
/// one run at a time, and retries a failure after [retryDelay].
class Syncer {
  Syncer(this.run);
  final Future<String?> Function() run;
  Timer? _retry;
  bool _running = false;
  bool _again = false;
  int _fails = 0;

  void kick() {
    _retry?.cancel();
    _retry = null;
    if (_running) {
      _again = true;
      return;
    }
    _go();
  }

  Future<void> _go() async {
    _running = true;
    String? err;
    try {
      err = await run();
    } catch (e) {
      err = '$e';
    }
    _running = false;
    if (_again) {
      _again = false;
      _go();
      return;
    }
    if (err == null) {
      _fails = 0;
    } else {
      _retry = Timer(Duration(seconds: retryDelay(_fails)), kick);
      _fails++;
    }
  }

  void dispose() => _retry?.cancel();
}
