import 'dart:convert';
import 'dart:io';

import 'package:app/db.dart';
import 'package:app/models.dart';
import 'package:app/native.dart';
import 'package:app/repo.dart';
import 'package:app/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late Database db;
  late FakeNative native;
  late Repo repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('butcher');
    db = await openButcherDb(databaseFactoryFfi, p.join(tmp.path, dbName));
    native = FakeNative();
    var t = 1700000000000;
    repo = Repo(db, Prefs(native), clock: () => t++);
    await repo.init();
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('the request is the same as the Kotlin app sent', () {
    final q = neonQuery(syncTables[2], Sale('s1', 'p1', 50.0, 38.0, 1.316, 'paid', true, 1700000000000).toMap(), 1700000000500);
    expect(q['query'],
        'INSERT INTO sales (uuid, product_uuid, total, price_per_kg, kg, kind, credit, device_time, sent_device_time) '
        'VALUES (\$1::uuid, \$2::uuid, \$3::double precision, \$4::double precision, \$5::double precision, \$6::text, '
        '\$7::boolean, to_timestamp(\$8::double precision / 1000), to_timestamp(\$9::double precision / 1000)) ON CONFLICT DO NOTHING');
    expect(q['params'], ['s1', 'p1', '50.0', '38.0', '1.316', 'paid', 'true', '1700000000000', '1700000000500']);
  });

  test('a null price (hide event) and a null sale link go up as JSON null', () {
    final h = neonQuery(syncTables[0], ProductEvent('e', 'p', 'x', 'hide', null, 5).toMap(), 6);
    expect((h['params'] as List)[4], isNull);
    final c = neonQuery(syncTables[9], CreditEvent('c', 'علي', 3.0, 'pay', null, 5).toMap(), 6);
    expect((c['params'] as List)[4], isNull);
    expect(jsonEncode(c), contains('null'));
  });

  test('pushAll sends every table, marks rows, and sends nothing twice', () async {
    await repo.addProduct('علوش', 38);
    await repo.addSale(const ProductView('p1', 'علوش', 38, false), 'paid', 76, null, 'علي');
    final sent = <String>[];
    final client = MockClient((r) async {
      expect(r.headers['Neon-Connection-String'], 'postgres://x');
      for (final q in (jsonDecode(r.body)['queries'] as List)) {
        sent.add((q['query'] as String).split(' ')[2]);
      }
      return http.Response('{}', 200);
    });
    final neon = Neon(client, url: 'https://h/sql', conn: 'postgres://x');
    expect(await pushAll(db, Prefs(native), neon), isNull);
    expect(sent, ['product_events', 'sales', 'credit_events']);
    expect(await Prefs(native).lastSync(), greaterThan(0));
    sent.clear();
    expect(await pushAll(db, Prefs(native), neon), isNull);
    expect(sent, isEmpty);
  });

  test('a failed table does not stop the others and stays unsent', () async {
    await repo.addProduct('علوش', 38);
    await repo.addCredit('علي', 10, 'debt');
    final client = MockClient((r) async =>
        r.body.contains('credit_events') ? http.Response('relation does not exist', 400) : http.Response('{}', 200));
    final err = await pushAll(db, Prefs(native), Neon(client, url: 'https://h/sql', conn: 'c'));
    expect(err, contains('credit_events: HTTP 400'));
    expect(await Dao(db).unsent('product_events'), isEmpty);
    expect((await Dao(db).unsent('credit_events')).length, 1);
  });

  test('a failed table in the middle: the tables after it still go up', () async {
    await repo.addSale(const ProductView('p1', 'علوش', 38, false), 'paid', 76, null, 'علي'); // sales + credit_events
    await repo.addPurchase('علوش كامل', 30, 28, 500); // purchases, the last table
    final client =
        MockClient((r) async => r.body.contains('INSERT INTO sales ') ? http.Response('bad', 500) : http.Response('{}', 200));
    final err = await pushAll(db, Prefs(native), Neon(client, url: 'https://h/sql', conn: 'c'));
    expect(err, startsWith('sales: HTTP 500'));
    expect((await Dao(db).unsent('sales')).length, 1);
    expect(await Dao(db).unsent('credit_events'), isEmpty);
    expect(await Dao(db).unsent('purchases'), isEmpty);
  });

  test('retry wait grows and stops at 5 minutes, even after many failures', () {
    expect([for (var i = 0; i < 6; i++) retryDelay(i)], [30, 60, 120, 240, 300, 300]);
    expect(retryDelay(59), 300);
    expect(retryDelay(1000), 300);
  });

  test('no network: error text, nothing marked', () async {
    await repo.addProduct('علوش', 38);
    final client = MockClient((r) async => throw const SocketException('no route'));
    final err = await pushAll(db, Prefs(native), Neon(client, url: 'https://h/sql', conn: 'c'));
    expect(err, contains('no route'));
    expect((await Dao(db).unsent('product_events')).length, 1);
  });

  test('Syncer retries a failure and runs again after a save during a run', () async {
    var runs = 0;
    final s = Syncer(() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return null;
    });
    s.kick();
    s.kick(); // during the run: one more run after it
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 2);
    s.dispose();
  });
}
