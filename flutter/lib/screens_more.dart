import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'logic.dart';
import 'models.dart';
import 't.dart';
import 'ui.dart';

/// Credit: the list of people with what they owe, a new name, and the amount.
class CreditScreen extends StatefulWidget {
  const CreditScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends State<CreditScreen> {
  String mode = 'list', person = '', amount = '';

  void clear() => setState(() {
        mode = 'list';
        person = '';
        amount = '';
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final events = repo.creditEvents;
    final live = liveCredits(events, repo.voidedIds.toSet());
    final owed = balances(live);
    final people = sortedByDesc(peopleByRecent(live), (p) => owed[p] ?? 0.0);
    final a = parseNum(amount);

    void save(String kind) {
      final v = a;
      final p = canonical(person, people);
      if (v != null && v > 0 && p.isNotEmpty) {
        unawaited(repo.addCredit(p, v, kind));
        clear();
      }
    }

    c.slot.handler = () {
      if (mode == 'list') return false;
      clear();
      return true;
    };

    switch (mode) {
      case 'list':
        // Only rows typed here. A credit sale is undone from بيعة or البيعات.
        final u = live.firstWhereOrNull((e) => e.saleUuid == null);
        final sign = u?.kind == 'pay' ? '-' : '+';
        return vcol(key: const ValueKey('list'), [
          Bar([
            Small(T.back, onTap: c.back),
            barTitle(T.credits),
            Small(u != null ? '${T.undo} ${u.person} $sign${fmtNum(u.amount)}' : T.undo, enabled: u != null, width: 240,
                onTap: () {
              if (u != null) unawaited(repo.voidRow('credit_events', u.uuid));
            }),
            Small(T.newPerson, width: 150, onTap: () {
              clear();
              setState(() => mode = 'name');
            }),
          ]),
          if (people.isEmpty) const Text(T.noCredit, style: TextStyle(fontSize: 24, color: Colors.black)),
          Expanded(
            child: PagedGrid<String>(people, 3, 4, (p) {
              final b = owed[p] ?? 0.0;
              return Plain('$p\n${fmtNum(b)}', dim: b <= 0, size: 20, onTap: () => setState(() {
                    person = p;
                    amount = '';
                    mode = 'amount';
                  }));
            }),
          ),
        ]);
      case 'name':
        return NamePicker(
          key: const ValueKey('name'),
          native: c.native,
          title: T.newPerson,
          value: person,
          onChange: (v) => setState(() => person = v),
          suggestions: people,
          back: clear,
          action: T.next,
          actionEnabled: cleanName(person).isNotEmpty,
          onAction: () => setState(() {
            person = canonical(person, people);
            mode = 'amount';
          }),
        );
      default:
        return hrow(key: const ValueKey('amount'), [
          w(1.4, NumPad(amount, (v) => setState(() => amount = v))),
          w(1, vcol([
            BigTitle('$person: ${T.owes} ${fmtNum(owed[person] ?? 0.0)}'),
            w(1, Readout(T.amount, amount, true, onTap: () {})),
            w(1, Plain(T.back, size: 20, onTap: clear)),
            w(1.2, Plain(T.addDebt, enabled: a != null && a > 0, size: 22, onTap: () => save('debt'))),
            w(1.2, Plain(T.paidBack, enabled: a != null && a > 0, size: 22, onTap: () => save('pay'))),
          ])),
        ]);
    }
  }
}

/// Personal spending: the amount, then optional details.
class SpendingScreen extends StatefulWidget {
  const SpendingScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<SpendingScreen> createState() => _SpendingScreenState();
}

class _SpendingScreenState extends State<SpendingScreen> {
  String mode = 'amount', amount = '', details = '';

  void clear() => setState(() {
        mode = 'amount';
        amount = '';
        details = '';
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final spends = repo.liveCashMoves.where((m) => m.amount < 0).toList();
    final a = parseNum(amount);
    final today = startOfDay(1);
    final todaySum = r3(sumOf(spends.where((m) => m.deviceTime >= today), (CashMove m) => -m.amount));
    final reasons = distinct(spends.map((m) => m.reason).where((r) => r.trim().isNotEmpty));
    c.slot.handler = () {
      if (mode == 'amount') return false;
      setState(() => mode = 'amount');
      return true;
    };

    if (mode == 'details') {
      return NamePicker(
        key: const ValueKey('details'),
        native: c.native,
        title: T.details,
        value: details,
        onChange: (v) => setState(() => details = v),
        suggestions: reasons,
        back: () => setState(() => mode = 'amount'),
        action: T.save,
        actionEnabled: a != null && a > 0,
        appendVoice: true,
        onAction: () {
          final v = a;
          final d = cleanName(details);
          if (v != null && v > 0) {
            unawaited(repo.addSpending(v, d));
            clear();
          }
        },
      );
    }

    final u = spends.firstOrNull;
    return hrow(key: const ValueKey('amount'), [
      w(1.4, NumPad(amount, (v) => setState(() => amount = v))),
      w(1, vcol([
        BigTitle('${T.spend}: ${T.today} ${fmtNum(todaySum)}'),
        w(1, Readout(T.amount, amount, true, onTap: () {})),
        w(1, Plain(T.back, size: 20, onTap: c.back)),
        w(1, Plain(u != null ? '${T.undo} ${fmtNum(-u.amount)}' : T.undo, enabled: u != null, size: 20, onTap: () {
          if (u != null) unawaited(repo.voidRow('cash_moves', u.uuid));
        })),
        w(1.5, Plain(T.next, enabled: a != null && a > 0, size: 24, onTap: () => setState(() => mode = 'details'))),
      ])),
    ]);
  }
}

/// Supplier purchase: the item (old items suggested), then kg, price per kg, and money given.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  String mode = 'name', item = '', kg = '', price = '', paid = '', field = 'kg';

  void clear() => setState(() {
        mode = 'name';
        item = '';
        kg = '';
        price = '';
        paid = '';
        field = 'kg';
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final purchases = repo.livePurchases;
    final items = distinct(purchases.map((p) => p.item).where((i) => i.isNotEmpty));
    final owed = supplierOwed(purchases);

    // Fills the last kg and price used for this item. Newest purchase comes first.
    void openItem(String name) {
      final n = cleanName(name);
      final last = purchases.firstWhereOrNull((p) => p.item.toLowerCase() == n.toLowerCase());
      setState(() {
        item = last?.item ?? n;
        kg = last != null ? fmtNum(last.kg) : '';
        price = last != null ? fmtNum(last.pricePerKg) : '';
        paid = '';
        field = 'kg';
        mode = 'nums';
      });
    }

    c.slot.handler = () {
      if (mode == 'name') return false;
      setState(() => mode = 'name');
      return true;
    };

    if (mode == 'name') {
      final u = purchases.firstOrNull;
      return NamePicker(
        key: const ValueKey('name'),
        native: c.native,
        title: T.whatBought,
        value: item,
        onChange: (v) => setState(() => item = v),
        suggestions: items,
        back: c.back,
        action: T.next,
        actionEnabled: cleanName(item).isNotEmpty,
        onAction: () => openItem(item),
        onPick: openItem,
        extra: [
          Small(u != null ? '${T.undo} ${u.item.isEmpty ? fmtNum(u.paid) : u.item}' : T.undo, enabled: u != null, width: 150,
              onTap: () {
            if (u != null) unawaited(repo.voidRow('purchases', u.uuid));
          }),
          Small(T.payOnly, width: 120, onTap: () => setState(() {
                item = '';
                kg = '';
                price = '';
                paid = '';
                field = 'paid';
                mode = 'nums';
              })),
        ],
      );
    }

    final payOnly = item.isEmpty;
    final k = parseNum(kg);
    final p = parseNum(price);
    final g = paid.isEmpty ? 0.0 : parseNum(paid);
    final cost = !payOnly && k != null && p != null ? r3(k * p) : 0.0;
    final valid = g != null && g >= 0 && (payOnly ? g > 0 : k != null && k > 0 && p != null && p > 0);
    final current = switch (field) { 'price' => price, 'paid' => paid, _ => kg };
    void set(String v) => setState(() {
          switch (field) {
            case 'price':
              price = v;
            case 'paid':
              paid = v;
            default:
              kg = v;
          }
        });

    return hrow(key: const ValueKey('nums'), [
      w(1.4, NumPad(current, set)),
      w(1, vcol([
        BigTitle(payOnly ? T.payOnly : item),
        if (!payOnly) ...[
          w(1, Readout(T.kilo, kg, field == 'kg', onTap: () => setState(() => field = 'kg'))),
          w(1, Readout(T.price, price, field == 'price', onTap: () => setState(() => field = 'price'))),
        ],
        w(1, Readout(T.gave, paid, field == 'paid', onTap: () => setState(() => field = 'paid'))),
        if (!payOnly) line('${T.total}: ${fmtNum(cost)}'),
        line('${T.oweAfter}: ${fmtNum(owed + cost - (g ?? 0.0))}', size: 18, bold: false),
        w(1.2, hrow([
          w(1, Plain(T.back, size: 20, onTap: () => setState(() => mode = 'name'))),
          w(1.4, Plain(T.save, enabled: valid, size: 24, onTap: () {
            if (!valid) return;
            final i = item;
            final kv = k ?? 0.0;
            final pv = p ?? 0.0;
            final gv = g;
            unawaited(repo.addPurchase(i, payOnly ? 0.0 : kv, payOnly ? 0.0 : pv, gv));
            clear();
          })),
        ])),
      ])),
    ]);
  }
}

/// Placeholder dashboard: pick the days, see each product's kg and money, and the totals.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int days = 1;
  List<Sale> sales = [];
  int _ask = 0;

  Future<void> _load() async {
    final ask = ++_ask;
    final r = await widget.c.repo.salesSince(startOfDay(days));
    if (mounted && ask == _ask) setState(() => sales = r);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    _load(); // new data saved somewhere
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final since = startOfDay(days);
    final names = {for (final p in foldProducts(repo.productEvents)) p.uuid: p.name};
    final purchases = repo.livePurchases.where((p) => p.deviceTime >= since).toList();
    final spends = repo.liveCashMoves.where((m) => m.deviceTime >= since && m.amount < 0).toList();
    final credits = liveCredits(repo.creditEvents, repo.voidedIds.toSet()).where((e) => e.deviceTime >= since).toList();

    final groups = <String, List<Sale>>{};
    for (final s in sales) {
      groups.putIfAbsent(s.productUuid, () => []).add(s);
    }
    final rows = sortedByDesc(
      [for (final g in groups.entries) (names[g.key] ?? '?', r3(sumOf(g.value, (Sale s) => s.kg)), r3(sumOf(g.value, (Sale s) => s.total)))],
      (r) => r.$3,
    );
    final sold = r3(sumOf(sales, (Sale s) => s.total));
    final bought = r3(sumOf(purchases, (Purchase p) => p.cost));
    final gave = r3(sumOf(purchases, (Purchase p) => p.paid));
    final spent = r3(sumOf(spends, (CashMove m) => -m.amount));
    final newDebt = r3(sumOf(credits.where((e) => e.kind == 'debt'), (CreditEvent e) => e.amount));
    final paidBack = r3(sumOf(credits.where((e) => e.kind == 'pay'), (CreditEvent e) => e.amount));
    final totals = [
      (T.sold, sold), (T.creditGiven, newDebt), (T.creditBack, paidBack),
      (T.bought, bought), (T.gave, gave), (T.spend, spent),
      // Cash that should be in the till from these days: sales not on credit, plus credit paid back, minus money out.
      (T.cash, r3(sold - newDebt + paidBack - gave - spent)),
    ];

    return vcol([
      Bar([
        Small(T.back, onTap: c.back),
        barTitle(T.dash),
        for (final (d, label) in const [(1, T.today), (3, T.days3), (7, T.week), (30, T.month)])
          Small(label, on: days == d, width: 90, onTap: () {
            setState(() => days = d);
            _load();
          }),
      ]),
      Expanded(
        child: hrow([
          w(1.4, vcol([
            if (rows.isEmpty) const Text(T.noSales, style: TextStyle(fontSize: 24, color: Colors.black)),
            Expanded(
              child: PagedGrid<(String, double, double)>(rows, 6, 1,
                  (r) => Plain('${r.$1}   ${fmtNum(r.$2)} ${T.kg}   ${fmtNum(r.$3)} ${T.dt}', size: 18, onTap: () {})),
            ),
          ])),
          w(1, vcol([for (final (label, v) in totals) line('$label: ${fmtNum(v)}')])),
        ]),
      ),
    ]);
  }
}
