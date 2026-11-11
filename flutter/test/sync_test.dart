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

  group('pull (Neon to phone)', () {
    // A fake Neon that answers reads with the rows given, as text, like the real one with ::text casts.
    MockClient neonWith(Map<String, List<Map<String, Object?>>> tables, {List<String>? asked}) => MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (body.containsKey('queries')) return http.Response('{}', 200); // a send
          final q = body['query'] as String;
          asked?.add(q);
          final table = q.split(' FROM ')[1].split(' ')[0];
          final cursor = int.parse((body['params'] as List)[0] as String);
          final rows = (tables[table] ?? []).where((x) => int.parse(x['uploaded_us'] as String) >= cursor).toList();
          return http.Response.bytes(utf8.encode(jsonEncode({'rows': rows})), 200); // no charset, like Neon
        });

    test('the read query asks every column as text, in milliseconds', () {
      final q = pullQuery(syncTables[2], 123);
      expect(q['query'], startsWith('SELECT uuid::text AS uuid, product_uuid::text AS product_uuid, total::text AS total, '));
      expect(q['query'], contains('(extract(epoch from device_time) * 1000)::bigint::text AS device_time'));
      expect(q['query'], contains('FROM sales WHERE uploaded_at >= to_timestamp(\$1::double precision / 1000000)'));
      expect(q['params'], ['123']);
    });

    test('rows from another phone come down once, marked sent; a void from Neon cancels the sale', () async {
      final neon = Neon(
          neonWith({
            'sales': [
              {'uuid': 's9', 'product_uuid': 'p1', 'total': '76', 'price_per_kg': '38', 'kg': '2', 'kind': 'paid',
                'credit': 'true', 'device_time': '1700000000000', 'uploaded_us': '1700000000000001'},
            ],
            'credit_events': [
              {'uuid': 'c9', 'person': 'علي', 'amount': '76', 'kind': 'debt', 'sale_uuid': 's9',
                'device_time': '1700000000000', 'uploaded_us': '1700000000000002'},
            ],
            'product_events': [
              {'uuid': 'e9', 'product_uuid': 'p1', 'name': 'علوش', 'kind': 'hide', 'price_per_kg': null,
                'device_time': '1', 'uploaded_us': '5'},
            ],
          }),
          url: 'https://h/sql',
          conn: 'c');
      expect(await pullAll(db, Prefs(native), neon), isNull);
      expect(await pullAll(db, Prefs(native), neon), isNull); // twice: still one row each
      final d = Dao(db);
      final s = (await d.liveSales()).single;
      expect([s.uuid, s.total, s.kg, s.credit, s.deviceTime, s.synced], ['s9', 76.0, 2.0, true, 1700000000000, true]);
      expect((await d.creditEvents()).single.saleUuid, 's9');
      expect((await d.creditEvents()).single.person, 'علي'); // Arabic survives the trip
      expect((await d.productEvents()).single.pricePerKg, isNull);
      expect(await d.unsent('sales'), isEmpty); // not sent back
      expect(await Prefs(native).pullCursor('sales'), 1700000000000001);
      expect(await Prefs(native).lastSync(), greaterThan(0));

      final withVoid = Neon(
          neonWith({
            'voids': [
              {'uuid': 'v9', 'target_table': 'sales', 'target_uuid': 's9', 'device_time': '1700000001000',
                'uploaded_us': '1700000001000000'},
            ],
          }),
          url: 'https://h/sql',
          conn: 'c');
      await pullAll(db, Prefs(native), withVoid);
      expect(await d.liveSales(), isEmpty);
    });

    test('a row the phone already has is not changed', () async {
      await repo.addSpending(10, 'ضو');
      final mine = (await Dao(db).liveCashMoves()).single;
      final neon = Neon(
          neonWith({
            'cash_moves': [
              {'uuid': mine.uuid, 'amount': '-999', 'reason': 'x', 'device_time': '1', 'uploaded_us': '9'},
            ],
          }),
          url: 'https://h/sql',
          conn: 'c');
      await pullAll(db, Prefs(native), neon);
      expect((await Dao(db).liveCashMoves()).single.amount, -10.0);
    });

    test('a full page asks again from the newest time; it stops', () async {
      final many = [
        for (var i = 0; i < pullPage + 20; i++)
          {'uuid': 'u$i', 'amount': '-1', 'reason': '', 'device_time': '1', 'uploaded_us': '${1000 + i ~/ 50}'},
      ];
      final asked = <String>[];
      final client = MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final q = body['query'] as String;
        if (!q.contains('FROM cash_moves ')) return http.Response('{"rows":[]}', 200);
        asked.add(q);
        final cursor = int.parse((body['params'] as List)[0] as String);
        final rows = many.where((x) => int.parse(x['uploaded_us']!) >= cursor).take(pullPage).toList();
        return http.Response.bytes(utf8.encode(jsonEncode({'rows': rows})), 200); // no charset, like Neon
      });
      expect(await pullAll(db, Prefs(native), Neon(client, url: 'https://h/sql', conn: 'c')), isNull);
      expect((await Dao(db).liveCashMoves()).length, pullPage + 20);
      expect(asked.length, 2);
    });

    test('reading not allowed yet (no GRANT): error text, the phone data stays', () async {
      await repo.addProduct('علوش', 38);
      final client = MockClient((r) async => r.body.contains('"queries"')
          ? http.Response('{}', 200)
          : http.Response('{"message":"permission denied for table product_events"}', 400));
      final err = await pullAll(db, Prefs(native), Neon(client, url: 'https://h/sql', conn: 'c'));
      expect(err, contains('permission denied'));
      expect((await Dao(db).productEvents()).length, 1);
    });
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
