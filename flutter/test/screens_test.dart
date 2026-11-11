import 'dart:io';

import 'package:app/app.dart';
import 'package:app/db.dart';
import 'package:app/logic.dart';
import 'package:app/models.dart';
import 'package:app/native.dart';
import 'package:app/repo.dart';
import 'package:app/sync.dart';
import 'package:app/t.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// Real Arabic font, so the screen images can be read (tests use box glyphs by default).
Future<void> loadFonts() async {
  final l = FontLoader('Roboto');
  for (final f in ['IBMPlexSansArabic-Regular.ttf', 'IBMPlexSansArabic-Bold.ttf']) {
    final b = File('/usr/share/fonts/truetype/ibm-plex/$f').readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

class World {
  World(this.db, this.native, this.repo);
  final Database db;
  final FakeNative native;
  final Repo repo;
}

/// Realme C21-Y sideways: 1600 x 720 px at 2x = 800 x 360 dp.
Future<World> start(WidgetTester tester, {Future<void> Function(Repo)? data, int Function()? clock}) async {
  tester.view.physicalSize = const Size(1600, 720);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final w = await tester.runAsync(() async {
    final dir = Directory.systemTemp.createTempSync('butcher');
    final db = await openButcherDb(databaseFactoryFfiNoIsolate, '${dir.path}/$dbName');
    addTearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
    final native = FakeNative();
    final repo = Repo(db, Prefs(native), clock: clock);
    await repo.init(firstInstallTime: DateTime.now().millisecondsSinceEpoch);
    await repo.seedProducts();
    if (data != null) await data(repo);
    return World(db, native, repo);
  });
  final neon = Neon(MockClient((r) async => http.Response('{}', 200)), url: '', conn: '');
  await tester.pumpWidget(ButcherApp(Deps(w!.repo, w.native, () async => null, neon)));
  await settle(tester);
  return w;
}

/// Lets database writes finish and the screen redraw.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, String text, {int index = 0}) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'no "$text" on screen');
  await tester.tap(f.at(index));
  await settle(tester);
}

Future<void> type(WidgetTester tester, String digits) async {
  for (final ch in digits.split('')) {
    await tap(tester, ch);
  }
}

Future<void> shot(String name) => expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

/// Prices for a few products, as the butcher sets them.
Future<void> prices(Repo r) async {
  final p = foldProducts(r.productEvents);
  await r.setPrice(p[0], 38); // علوش
  await r.setPrice(p[1], 32); // هبرة عجول
  await r.setPrice(p[4], 45); // فيلي
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

void main() {
  sqfliteFfiInit();
  setUpAll(loadFonts);

  testWidgets('home screen', (tester) async {
    await start(tester);
    expect(find.text(T.sell), findsOneWidget);
    for (final l in [T.goods, T.history, T.credits, T.buy, T.spend, T.dash]) {
      expect(find.text(l), findsOneWidget);
    }
    await shot('01_home');
  });

  testWidgets('sale: unpriced products cannot be sold; paid sale is saved with kg', (tester) async {
    final w = await start(tester, data: prices);
    await tap(tester, T.sell);
    await shot('02_sale_pick');
    await tap(tester, 'كرشة'); // no price: nothing happens
    expect(find.text(T.pick), findsOneWidget);
    await tap(tester, 'علوش');
    await type(tester, '76');
    await shot('03_sale_amount');
    await tap(tester, T.save);
    expect(find.text(T.pick), findsOneWidget); // back to the grid for the next sale
    final s = w.repo.liveSales.single;
    expect([s.total, s.kg, s.kind, s.credit], [76.0, 2.0, 'paid', false]);
    expect(find.text('${T.undo} علوش 76'), findsOneWidget);
    await tap(tester, '${T.undo} علوش 76');
    expect(w.repo.liveSales, isEmpty);
  });

  testWidgets('sale: discount needs the kg; the back button goes back one step', (tester) async {
    final w = await start(tester, data: prices);
    await tap(tester, T.sell);
    await tap(tester, 'فيلي');
    await tap(tester, T.discount);
    await type(tester, '40');
    expect(tester.widget<Text>(find.text(T.save)).style!.color, Colors.grey); // kg missing
    await tap(tester, '${T.kilo}: ');
    await type(tester, '1');
    await tap(tester, T.save);
    final s = w.repo.liveSales.single;
    expect([s.total, s.kg, s.kind], [40.0, 1.0, 'discount']);

    await tap(tester, 'فيلي');
    await back(tester);
    expect(find.text(T.pick), findsOneWidget); // not home
    await back(tester);
    expect(find.text(T.sell), findsOneWidget); // now home
  });

  testWidgets('credit sale asks the name, then shows in الكريدي; pay back', (tester) async {
    final w = await start(tester, data: prices);
    await tap(tester, T.sell);
    await tap(tester, 'علوش');
    await type(tester, '57');
    await tap(tester, T.credit);
    await tap(tester, T.next);
    expect(find.text(T.who), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  محمد   علي ');
    await settle(tester);
    await shot('04_credit_name');
    await tap(tester, T.save);
    expect(w.repo.liveSales.single.credit, true);

    await back(tester);
    await tap(tester, T.credits);
    await shot('05_credit_list');
    await tap(tester, 'محمد علي\n57');
    await type(tester, '20');
    await tap(tester, T.paidBack);
    expect(balances(liveCredits(w.repo.creditEvents, w.repo.voidedIds.toSet())), {'محمد علي': 37.0});
    expect(find.text('محمد علي\n37'), findsOneWidget);

    // Same name typed with other spaces goes to the same person.
    await back(tester);
    await back(tester);
    await tap(tester, T.sell);
    await tap(tester, 'علوش');
    await type(tester, '3');
    await tap(tester, T.credit);
    await tap(tester, T.next);
    await tap(tester, 'محمد علي'); // the old name as a button
    await tap(tester, T.save);
    expect(balances(liveCredits(w.repo.creditEvents, w.repo.voidedIds.toSet())), {'محمد علي': 40.0});
  });

  testWidgets('voice fills the name box', (tester) async {
    final w = await start(tester);
    await tap(tester, T.credits);
    await tap(tester, T.newPerson);
    w.native.nextSpeech = 'صالح';
    await tap(tester, T.mic);
    expect(w.native.speechCalls, 1);
    expect(find.widgetWithText(TextField, 'صالح'), findsOneWidget);
  });

  testWidgets('goods: set a price, add a product, arrange', (tester) async {
    final w = await start(tester);
    await tap(tester, T.goods);
    await shot('06_goods');
    await tap(tester, 'علوش');
    await type(tester, '38');
    await tap(tester, T.save);
    expect(foldProducts(w.repo.productEvents).first.price, 38.0);

    await tap(tester, T.newGood);
    await tester.enterText(find.byType(TextField), 'مرقاز');
    await settle(tester);
    await tap(tester, T.next);
    await type(tester, '30');
    await tap(tester, T.add);
    expect(foldProducts(w.repo.productEvents).last.name, 'مرقاز');

    await tap(tester, T.arrange);
    await tap(tester, 'كرشة');
    await shot('07_arrange');
    await tap(tester, 'علوش');
    await tap(tester, T.done);
    final order = sortProducts(foldProducts(w.repo.productEvents), w.repo.order).map((p) => p.name).toList();
    expect(order.take(2), ['كرشة', 'علوش']);
    expect(w.native.data['butcher/product_order'], isNotNull);
  });

  testWidgets('history: edit and cancel a sale', (tester) async {
    final w = await start(tester, data: (r) async {
      await prices(r);
      final p = foldProducts(r.productEvents);
      await r.addSale(p[0], 'paid', 76, null, null);
    }, clock: () => DateTime(2026, 3, 1, 9, 30).millisecondsSinceEpoch); // fixed time: the image shows it
    expect(find.text(T.history), findsOneWidget);
    await tap(tester, T.history);
    expect(find.textContaining('01/03 09:30'), findsOneWidget);
    await shot('08_history');
    await tester.tap(find.textContaining('علوش  76.0'));
    await settle(tester);
    await tap(tester, '⌫');
    await tap(tester, '⌫');
    await tap(tester, '⌫');
    await tap(tester, '⌫');
    await type(tester, '95');
    await tap(tester, T.save);
    final s = w.repo.liveSales.single;
    expect([s.total, s.kg], [95.0, 2.5]);
    await tester.tap(find.textContaining('علوش  95.0'));
    await settle(tester);
    await tap(tester, T.undo);
    expect(w.repo.liveSales, isEmpty);
    expect(find.text(T.noSales), findsOneWidget);
  });

  testWidgets('spending with details, then undo', (tester) async {
    final w = await start(tester);
    await tap(tester, T.spend);
    await type(tester, '12.5');
    await shot('09_spend');
    await tap(tester, T.next);
    await tester.enterText(find.byType(TextField), 'ضو');
    await settle(tester);
    await tap(tester, T.save);
    expect(w.repo.liveCashMoves.single.amount, -12.5);
    expect(find.text('${T.spend}: ${T.today} 12.5'), findsOneWidget);
    await tap(tester, '${T.undo} 12.5');
    expect(w.repo.liveCashMoves, isEmpty);
  });

  testWidgets('purchase remembers the last kg and price of an item', (tester) async {
    final w = await start(tester);
    await tap(tester, T.buy);
    await tester.enterText(find.byType(TextField), 'علوش كامل');
    await settle(tester);
    await tap(tester, T.next);
    await type(tester, '30');
    await tap(tester, '${T.price}: ');
    await type(tester, '28.5');
    await tap(tester, '${T.gave}: ');
    await type(tester, '500');
    expect(find.text('${T.total}: 855'), findsOneWidget);
    expect(find.text('${T.oweAfter}: 355'), findsOneWidget);
    await shot('10_buy_numbers');
    await tap(tester, T.save);
    expect(w.repo.livePurchases.single.cost, 855.0);

    await tester.enterText(find.byType(TextField), 'علو');
    await settle(tester);
    await shot('11_buy_suggest');
    await tap(tester, 'علوش كامل'); // one tap opens it with the old values
    expect(find.text('${T.kilo}: 30'), findsOneWidget);
    expect(find.text('${T.price}: 28.5'), findsOneWidget);
    await tap(tester, '${T.kilo}: 30');
    await tap(tester, '⌫');
    await tap(tester, '⌫');
    await type(tester, '35');
    await tap(tester, T.save);
    await tester.enterText(find.byType(TextField), 'علوش كامل');
    await settle(tester);
    await tap(tester, T.next);
    expect(find.text('${T.kilo}: 35'), findsOneWidget); // the newest kg

    await back(tester);
    await tap(tester, T.payOnly);
    await type(tester, '100');
    await tap(tester, T.save);
    expect(w.repo.livePurchases.first.item, '');
    expect(supplierOwed(w.repo.livePurchases), r3(855 + 35 * 28.5 - 500 - 100));
  });

  testWidgets('dashboard totals and filters', (tester) async {
    await start(tester, data: (r) async {
      await prices(r);
      final p = foldProducts(r.productEvents);
      await r.addSale(p[0], 'paid', 76, null, null);
      await r.addSale(p[0], 'paid', 38, null, 'علي');
      await r.addSale(p[4], 'paid', 90, null, null);
      await r.addCredit('علي', 10, 'pay');
      await r.addPurchase('علوش كامل', 30, 28, 500);
      await r.addSpending(20, 'ضو');
    });
    await tap(tester, T.dash);
    await shot('12_dashboard');
    expect(find.text('${T.sold}: 204'), findsOneWidget);
    expect(find.text('${T.creditGiven}: 38'), findsOneWidget);
    // 204 - 38 + 10 - 500 - 20
    expect(find.text('${T.cash}: -344'), findsOneWidget);
    expect(find.text('علوش   3 ${T.kg}   114 ${T.dt}'), findsOneWidget);
    await tap(tester, T.week);
    expect(find.text('${T.sold}: 204'), findsOneWidget);
  });

  testWidgets('debug screen without Neon address says so', (tester) async {
    await start(tester);
    await tap(tester, T.test);
    await tap(tester, T.sendTest);
    expect(find.textContaining('NEON_SQL_URL empty'), findsOneWidget);
  });
}

// Keeps the analyzer quiet about the imported model types used only in closures.
// ignore: unused_element
typedef _K = (Sale, CreditEvent);
