import 'dart:io';

import 'package:app/db.dart';
import 'package:app/logic.dart';
import 'package:app/models.dart';
import 'package:app/native.dart';
import 'package:app/repo.dart';
import 'package:app/t.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  sqfliteFfiInit();
  final f = databaseFactoryFfi;
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('butcher'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> roomFile(int version, {bool withV2 = false}) async {
    final path = p.join(tmp.path, dbName);
    final db = await f.openDatabase(path);
    for (final s in roomV1) {
      await db.execute(s);
    }
    if (withV2) {
      await db.execute('CREATE TABLE IF NOT EXISTS `credit_events` (`uuid` TEXT NOT NULL, `person` TEXT NOT NULL, `amount` REAL NOT NULL, `kind` TEXT NOT NULL, `saleUuid` TEXT, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))');
      await db.execute('CREATE TABLE IF NOT EXISTS `purchases` (`uuid` TEXT NOT NULL, `item` TEXT NOT NULL, `kg` REAL NOT NULL, `pricePerKg` REAL NOT NULL, `cost` REAL NOT NULL, `paid` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, `synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))');
      await db.execute("INSERT INTO credit_events VALUES ('c1','علي',30.0,'debt',NULL,1000,1)");
    }
    // Rows the butcher already typed with the Kotlin app.
    await db.execute("INSERT INTO product_events VALUES ('e1','p1','علوش','create',0.0,100,1)");
    await db.execute("INSERT INTO product_events VALUES ('e2','p1','علوش','price',38.0,200,0)");
    await db.execute("INSERT INTO sales VALUES ('s1','p1',76.0,38.0,2.0,'paid',0,300,0)");
    await db.execute("INSERT INTO voids VALUES ('v1','sales','s0',400,1)");
    await db.setVersion(version);
    await db.close();
    return path;
  }

  test('fresh install creates every table with the Room columns', () async {
    final db = await openButcherDb(f, p.join(tmp.path, dbName));
    expect(await db.getVersion(), 2);
    final names = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
    expect(names, containsAll(['product_events', 'supplier_events', 'sales', 'voids', 'carcasses', 'waste', 'closings',
      'cash_moves', 'stock_counts', 'credit_events', 'purchases']));
    final cols = (await db.rawQuery('PRAGMA table_info(sales)')).map((r) => '${r['name']} ${r['type']} ${r['notnull']}').toList();
    expect(cols, ['uuid TEXT 1', 'productUuid TEXT 1', 'total REAL 1', 'pricePerKg REAL 1', 'kg REAL 1', 'kind TEXT 1',
      'credit INTEGER 1', 'deviceTime INTEGER 1', 'synced INTEGER 1']);
    await db.close();
  });

  test('old Kotlin database v1 opens, keeps every row, and gains the v2 tables', () async {
    final path = await roomFile(1);
    final db = await openButcherDb(f, path);
    expect(await db.getVersion(), 2);
    final d = Dao(db);
    final products = foldProducts(await d.productEvents());
    expect(products.single.name, 'علوش');
    expect(products.single.price, 38.0);
    expect((await d.liveSales()).single.total, 76.0);
    expect(await d.voidedIds(), ['s0']);
    expect(await d.creditEvents(), isEmpty); // new table, empty
    expect(await d.livePurchases(), isEmpty);
    // Upload markers survive: e1 was sent, e2 was not.
    expect((await d.unsent('product_events')).map((r) => r['uuid']), ['e2']);
    await db.close();
  });

  test('old Kotlin database v2 opens without change', () async {
    final path = await roomFile(2, withV2: true);
    final db = await openButcherDb(f, path);
    final d = Dao(db);
    expect((await d.creditEvents()).single.person, 'علي');
    expect((await d.liveSales()).length, 1);
    // Room's own table is left alone (harmless).
    expect((await db.rawQuery('SELECT COUNT(*) c FROM room_master_table')).first['c'], 1);
    await db.close();
  });

  group('Repo', () {
    late Database db;
    late FakeNative native;
    late Repo repo;
    var kicks = 0;
    var clock = 1000;

    setUp(() async {
      db = await openButcherDb(f, p.join(tmp.path, dbName));
      native = FakeNative();
      kicks = 0;
      clock = 1000;
      repo = Repo(db, Prefs(native), kick: () => kicks++, clock: () => clock++);
      await repo.init();
    });
    tearDown(() => db.close());

    test('seeds the 15 products once', () async {
      await repo.seedProducts();
      await repo.seedProducts();
      expect(foldProducts(repo.productEvents).map((p) => p.name), starterProducts);
      expect(await Prefs(native).seedDone(), true);
    });

    test('never seeds over existing products even if the flag is lost', () async {
      await repo.addProduct('علوش', 38);
      await repo.seedProducts();
      expect(foldProducts(repo.productEvents).length, 1);
    });

    test('paid sale computes kg from the price and asks for a sync', () async {
      await repo.addSale(const ProductView('p1', 'علوش', 38, false), 'paid', 50, null, null);
      final s = repo.liveSales.single;
      expect(s.kg, 1.316); // 50 / 38
      expect(s.credit, false);
      expect(kicks, 1);
    });

    test('credit sale saves the debt with it; undo removes the debt', () async {
      await repo.addSale(const ProductView('p1', 'علوش', 40, false), 'paid', 80, null, 'علي');
      var live = liveCredits(repo.creditEvents, repo.voidedIds.toSet());
      expect(balances(live), {'علي': 80.0});
      expect(repo.liveSales.single.credit, true);
      await repo.undoSale(repo.liveSales.single);
      live = liveCredits(repo.creditEvents, repo.voidedIds.toSet());
      expect(balances(live), isEmpty);
      expect(repo.liveSales, isEmpty);
    });

    test('editing a credit sale moves the debt to the new amount', () async {
      await repo.addSale(const ProductView('p1', 'علوش', 40, false), 'paid', 80, null, 'علي');
      final old = repo.liveSales.single;
      await repo.editSale(old, 60, 1.5);
      final n = repo.liveSales.single;
      expect(n.uuid, isNot(old.uuid));
      expect(n.total, 60.0);
      expect(n.deviceTime, old.deviceTime); // keeps its time
      expect(n.credit, true);
      final live = liveCredits(repo.creditEvents, repo.voidedIds.toSet());
      expect(balances(live), {'علي': 60.0});
      expect(live.single.saleUuid, n.uuid);
    });

    test('pay back lowers the balance; credit undo voids only typed rows', () async {
      await repo.addCredit('علي', 50, 'debt');
      await repo.addCredit('علي', 20, 'pay');
      expect(balances(liveCredits(repo.creditEvents, repo.voidedIds.toSet())), {'علي': 30.0});
      await repo.voidRow('credit_events', repo.creditEvents.first.uuid); // the payment
      expect(balances(liveCredits(repo.creditEvents, repo.voidedIds.toSet())), {'علي': 50.0});
    });

    test('spending is saved negative and can be undone', () async {
      await repo.addSpending(12.5, 'ضو');
      expect(repo.liveCashMoves.single.amount, -12.5);
      expect(repo.liveCashMoves.single.reason, 'ضو');
      await repo.voidRow('cash_moves', repo.liveCashMoves.single.uuid);
      expect(repo.liveCashMoves, isEmpty);
    });

    test('purchase cost is kg times price, newest first', () async {
      await repo.addPurchase('علوش كامل', 30, 28.5, 500);
      await repo.addPurchase('', 0, 0, 100);
      expect(repo.livePurchases.first.item, '');
      expect(repo.livePurchases.last.cost, 855.0);
      expect(supplierOwed(repo.livePurchases), 255.0);
    });

    test('order is saved in the Kotlin settings key', () async {
      repo.setOrder(['b', 'a']);
      await Future<void>.delayed(Duration.zero);
      expect(native.data['butcher/product_order'], 'b,a');
    });

    test('salesSince filters by time and drops voided sales', () async {
      await repo.addSale(const ProductView('p1', 'x', 10, false), 'paid', 10, null, null); // t=1000
      clock = 5000;
      await repo.addSale(const ProductView('p1', 'x', 10, false), 'paid', 20, null, null); // t=5000
      expect((await repo.salesSince(2000)).single.total, 20.0);
      await repo.undoSale(repo.liveSales.first);
      expect(await repo.salesSince(2000), isEmpty);
    });
  });
}
