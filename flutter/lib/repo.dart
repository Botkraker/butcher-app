import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'logic.dart';
import 'models.dart';
import 'native.dart';
import 't.dart';

/// Every save writes to the database first, then reloads what the screens show, then asks for a sync.
class Repo extends ChangeNotifier {
  Repo(this.db, this.prefs, {this.kick, int Function()? clock}) : _clock = clock ?? _now;
  final Database db;
  final Prefs prefs;
  final void Function()? kick;
  final int Function() _clock;
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Dao get _dao => Dao(db);

  List<ProductEvent> productEvents = [];
  Sale? lastLiveSale;
  List<Sale> liveSales = [];
  List<CreditEvent> creditEvents = [];
  List<String> voidedIds = [];
  List<Purchase> livePurchases = [];
  List<CashMove> liveCashMoves = [];
  List<String> order = [];
  int lastSync = 0;
  int firstInstall = 0;

  /// Reads the order and last sync time once, then the data.
  Future<void> init({int firstInstallTime = 0}) async {
    firstInstall = firstInstallTime;
    order = await prefs.order();
    lastSync = await prefs.lastSync();
    await reload();
  }

  Future<void> reload() async {
    final d = _dao;
    productEvents = await d.productEvents();
    lastLiveSale = await d.lastLiveSale();
    liveSales = await d.liveSales();
    creditEvents = await d.creditEvents();
    voidedIds = await d.voidedIds();
    livePurchases = await d.livePurchases();
    liveCashMoves = await d.liveCashMoves();
    notifyListeners();
  }

  Future<List<Sale>> salesSince(int since) => _dao.salesSince(since);

  Future<void> _after() async {
    await reload();
    kick?.call();
  }

  void setOrder(List<String> ids) {
    order = ids;
    notifyListeners();
    prefs.setOrder(ids);
  }

  void syncedAt(int t) {
    lastSync = t;
    notifyListeners();
  }

  /// The 15 starter products, once. The Kotlin app kept the same flag in the "seed" file.
  /// Also skipped when products already exist, so a lost flag can never add them twice.
  Future<void> seedProducts() async {
    if (await prefs.seedDone()) return;
    if ((await _dao.productEvents()).isNotEmpty) {
      await prefs.setSeedDone();
      return;
    }
    for (final n in starterProducts) {
      await _dao.insertProductEvent(ProductEvent(newId(), newId(), n, 'create', 0.0, _clock()));
    }
    await prefs.setSeedDone();
    await _after();
  }

  Future<void> addProduct(String name, double price) async {
    await _dao.insertProductEvent(ProductEvent(newId(), newId(), name, 'create', price, _clock()));
    await _after();
  }

  Future<void> setPrice(ProductView p, double price) async {
    await _dao.insertProductEvent(ProductEvent(newId(), p.uuid, p.name, 'price', price, _clock()));
    await _after();
  }

  Future<void> hide(ProductView p) async {
    await _dao.insertProductEvent(ProductEvent(newId(), p.uuid, p.name, 'hide', null, _clock()));
    await _after();
  }

  /// person is set for a credit sale: the sale and its debt are saved together.
  Future<void> addSale(ProductView p, String kind, double total, double? kgTyped, String? person) async {
    final kg = kgTyped ?? r3(total / p.price);
    final sale = Sale(newId(), p.uuid, total, p.price, kg, kind, person != null, _clock());
    await db.transaction((txn) async {
      final d = Dao(txn);
      await d.insertSale(sale);
      if (person != null) await d.insertCreditEvent(CreditEvent(newId(), person, total, 'debt', sale.uuid, sale.deviceTime));
    });
    await _after();
  }

  /// Edit is a void plus a new row, so the server keeps both. The sale keeps its time. A credit sale keeps its debt.
  Future<void> editSale(Sale s, double total, double kg) async {
    await db.transaction((txn) async {
      final d = Dao(txn);
      final debt = s.credit ? await d.creditForSale(s.uuid) : null;
      await d.insertVoid(VoidRow(newId(), 'sales', s.uuid, _clock()));
      final n = Sale(newId(), s.productUuid, total, s.pricePerKg, kg, s.kind, debt != null, s.deviceTime);
      await d.insertSale(n);
      if (debt != null) await d.insertCreditEvent(CreditEvent(newId(), debt.person, total, 'debt', n.uuid, debt.deviceTime));
    });
    await _after();
  }

  Future<void> undoSale(Sale s) => voidRow('sales', s.uuid);

  Future<void> voidRow(String table, String uuid) async {
    await _dao.insertVoid(VoidRow(newId(), table, uuid, _clock()));
    await _after();
  }

  Future<void> addCredit(String person, double amount, String kind) async {
    await _dao.insertCreditEvent(CreditEvent(newId(), person, amount, kind, null, _clock()));
    await _after();
  }

  /// Money taken from the till for the house. Saved as a negative cash move.
  Future<void> addSpending(double amount, String details) async {
    await _dao.insertCashMove(CashMove(newId(), -amount, details, _clock()));
    await _after();
  }

  Future<void> addPurchase(String item, double kg, double pricePerKg, double paid) async {
    await _dao.insertPurchase(Purchase(newId(), item, kg, pricePerKg, r3(kg * pricePerKg), paid, _clock()));
    await _after();
  }
}
