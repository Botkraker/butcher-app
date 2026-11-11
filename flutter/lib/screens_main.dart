import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'logic.dart';
import 'models.dart';
import 'sync.dart';
import 't.dart';
import 'ui.dart';

List<ProductView> visibleProducts(Ctx c) =>
    sortProducts(foldProducts(c.repo.productEvents).where((p) => !p.hidden).toList(), c.repo.order);

/// Green has a price, grey has none.
Widget productGrid(List<ProductView> products,
        {bool Function(ProductView)? pickable, String? highlight, required void Function(ProductView) onTap}) =>
    PagedGrid<ProductView>(
      products,
      4,
      5,
      (p) => Plain(p.name,
          on: p.uuid == highlight,
          enabled: pickable?.call(p) ?? true,
          dim: p.price <= 0,
          fill: green,
          size: 20,
          onTap: () => onTap(p)),
    );

class HomeScreen extends StatelessWidget {
  const HomeScreen(this.c, this.go, {super.key});
  final Ctx c;
  final void Function(String) go;

  @override
  Widget build(BuildContext context) {
    final last = c.repo.lastSync;
    final base = last > 0 ? last : c.repo.firstInstall;
    final stale = DateTime.now().millisecondsSinceEpoch - base > 3 * 24 * 3600 * 1000;
    final t = last > 0 ? fmtDateTime(last) : '—';
    const buttons = [
      [(T.goods, 'products'), (T.history, 'history')],
      [(T.credits, 'credits'), (T.buy, 'buy')],
      [(T.spend, 'spend'), (T.dash, 'dash')],
    ];
    return vcol([
      Expanded(
        child: hrow([
          w(2, Plain(T.sell, size: 72, onTap: () => go('sale'))),
          w(1.4, vcol([
            for (final row in buttons)
              Expanded(child: hrow([for (final (label, target) in row) Expanded(child: Plain(label, size: 26, onTap: () => go(target)))])),
          ])),
        ]),
      ),
      Row(children: [
        Expanded(
          child: Text(stale ? T.warn : '${T.lastSync}: $t',
              style: TextStyle(color: stale ? Colors.red : Colors.black, fontSize: 20)),
        ),
        GestureDetector(
          onTap: () => go('debug'),
          child: const Padding(padding: EdgeInsets.all(8), child: Text(T.test, style: TextStyle(fontSize: 18))),
        ),
      ]),
    ]);
  }
}

class SaleScreen extends StatefulWidget {
  const SaleScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  String? selected;
  bool discount = false, credit = false, askName = false, onKg = false;
  String person = '', total = '', kgText = '';

  void reset() => setState(() {
        total = '';
        kgText = '';
        credit = false;
        discount = false;
        onKg = false;
        askName = false;
        person = '';
        selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final products = visibleProducts(c);
    final lastSale = repo.lastLiveSale;
    final people = peopleByRecent(repo.creditEvents);
    final kind = discount ? 'discount' : 'paid';
    final typingKg = discount && onKg;
    final product = products.firstWhereOrNull((p) => p.uuid == selected);
    final totalNum = parseNum(total);
    final kgNum = parseNum(kgText);
    // Paid: total > 0. Discount: total >= 0 and the kg he really gave. Credit: total > 0.
    final valid = product != null &&
        product.price > 0 &&
        totalNum != null &&
        (discount ? totalNum >= 0 && kgNum != null && kgNum > 0 : totalNum > 0) &&
        (!credit || totalNum > 0);

    void save() {
      final p = product;
      final t = totalNum;
      final who = credit ? canonical(person, people) : null;
      if (p != null && t != null && valid && who != '') {
        guard(context, repo.addSale(p, kind, t, discount ? kgNum : null, who));
        reset();
      }
    }

    c.slot.handler = () {
      if (product == null) return false;
      if (askName) {
        setState(() => askName = false);
      } else {
        reset();
      }
      return true;
    };

    if (product == null) {
      final s = lastSale;
      final lastName = products.firstWhereOrNull((p) => p.uuid == s?.productUuid)?.name ?? '';
      return vcol(key: const ValueKey('pick'), [
        Bar([
          Small(T.back, onTap: c.back),
          barTitle(T.pick),
          Small(s != null ? '${T.undo} $lastName ${fmtNum(s.total)}' : T.undo,
              enabled: s != null, width: 240, onTap: () {
            if (s != null) guard(context, repo.undoSale(s));
          }),
        ]),
        Expanded(child: productGrid(products, pickable: (p) => p.price > 0, onTap: (p) => setState(() => selected = p.uuid))),
      ]);
    }

    if (askName) {
      return NamePicker(
        key: const ValueKey('who'),
        native: c.native,
        title: T.who,
        value: person,
        onChange: (v) => setState(() => person = v),
        suggestions: people,
        back: () => setState(() => askName = false),
        action: T.save,
        actionEnabled: cleanName(person).isNotEmpty,
        onAction: save,
      );
    }

    return hrow(key: const ValueKey('amount'), [
      w(1.4, vcol([
        w(0.6, Readout(T.total, total, !typingKg, onTap: () => setState(() => onKg = false))),
        if (discount) w(0.6, Readout(T.kilo, kgText, typingKg, onTap: () => setState(() => onKg = true))),
        w(3, typingKg ? NumPad(kgText, (v) => setState(() => kgText = v)) : NumPad(total, (v) => setState(() => total = v))),
      ])),
      w(1, vcol([
        BigTitle(product.name),
        w(1, Plain(T.back, size: 20, onTap: reset)),
        w(1, Plain(T.discount, on: discount, size: 20, onTap: () => setState(() {
              discount = !discount;
              onKg = false;
            }))),
        w(1, Plain(T.credit, on: credit, size: 20, onTap: () => setState(() => credit = !credit))),
        w(1.5, Plain(credit ? T.next : T.save, enabled: valid, size: 24, onTap: () {
          if (credit) {
            setState(() => askName = true);
          } else {
            save();
          }
        })),
      ])),
    ]);
  }
}

/// Four separate screens: the list, arranging, the new name, and the price.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String mode = 'list';
  String? selected, moving;
  String name = '', price = '';

  void clear() => setState(() {
        mode = 'list';
        selected = null;
        moving = null;
        name = '';
        price = '';
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final products = visibleProducts(c);
    final product = products.firstWhereOrNull((p) => p.uuid == selected);
    final pr = parseNum(price);
    c.slot.handler = () {
      if (mode == 'list') return false;
      clear();
      return true;
    };

    switch (mode) {
      case 'list':
        return vcol(key: const ValueKey('list'), [
          Bar([
            Small(T.back, onTap: c.back),
            barTitle(T.goods),
            Small(T.arrange, onTap: () {
              clear();
              setState(() => mode = 'arrange');
            }),
            Small(T.newGood, width: 180, onTap: () {
              clear();
              setState(() => mode = 'name');
            }),
          ]),
          Expanded(
            child: productGrid(products, onTap: (p) => setState(() {
                  selected = p.uuid;
                  price = p.price > 0 ? kStr(p.price) : '';
                  mode = 'price';
                })),
          ),
        ]);
      // Tap a product (it turns black), then tap the place where it should go.
      case 'arrange':
        return vcol(key: const ValueKey('arrange'), [
          Bar([barTitle(T.arrangeHelp), Small(T.done, onTap: clear)]),
          Expanded(
            child: productGrid(products, highlight: moving, onTap: (p) {
              final m = moving;
              if (m == null) {
                setState(() => moving = p.uuid);
              } else if (m == p.uuid) {
                setState(() => moving = null);
              } else {
                repo.setOrder(moveTo(products.map((x) => x.uuid).toList(), m, p.uuid));
                setState(() => moving = null);
              }
            }),
          ),
        ]);
      case 'name':
        return vcol(key: const ValueKey('name'), [
          Bar([
            Small(T.back, onTap: clear),
            barTitle(T.newGood),
            Small(T.next, enabled: name.trim().isNotEmpty, onTap: () => setState(() => mode = 'price')),
          ]),
          NameField(name, (v) => setState(() => name = v), label: T.name),
        ]);
      default:
        return hrow(key: const ValueKey('price'), [
          w(1.4, NumPad(price, (v) => setState(() => price = v))),
          w(1, vcol([
            BigTitle(product?.name ?? name),
            w(1, Readout(T.price, price, true, onTap: () {})),
            w(1, Plain(T.back, size: 20, onTap: clear)),
            if (product != null)
              w(1, Plain(T.remove, size: 20, onTap: () {
                guard(context, repo.hide(product));
                clear();
              })),
            w(1.5, Plain(product == null ? T.add : T.save, enabled: pr != null && pr > 0, size: 24, onTap: () {
              final v = pr;
              if (v == null) return;
              final p = product;
              final n = name.trim();
              guard(context, p != null ? repo.setPrice(p, v) : repo.addProduct(n, v));
              clear();
            })),
          ])),
        ]);
    }
  }
}

/// Two separate screens: the list of sales, and the edit of one sale.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int page = 0;
  String? selected;
  String value = '';

  void clear() => setState(() {
        selected = null;
        value = '';
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final repo = c.repo;
    final sales = repo.liveSales;
    final names = {for (final p in foldProducts(repo.productEvents)) p.uuid: p.name};
    const perPage = 5;
    final pages = (sales.length / perPage).ceil().clamp(1, 1 << 30);
    final shown = sales.skip((page < pages - 1 ? page : pages - 1) * perPage).take(perPage).toList();
    final sale = sales.firstWhereOrNull((s) => s.uuid == selected);
    final free = sale?.kind == 'free';
    final v = parseNum(value);
    c.slot.handler = () {
      if (sale == null) return false;
      clear();
      return true;
    };

    if (sale == null) {
      return vcol(key: const ValueKey('sales'), [
        Bar([
          Small(T.back, onTap: c.back),
          barTitle(T.history),
          Small(T.older, enabled: pages > 1, onTap: () => setState(() => page = (page + 1) % pages)),
        ]),
        if (sales.isEmpty) const Text(T.noSales, style: TextStyle(fontSize: 28, color: Colors.black)),
        for (var i = 0; i < perPage; i++)
          Expanded(
            child: i < shown.length
                ? () {
                    final s = shown[i];
                    return Plain(
                      '${names[s.productUuid] ?? ''}  ${kStr(s.total)}  ${fmtShort(s.deviceTime)}${s.credit ? '  ${T.credit}' : ''}',
                      size: 20,
                      onTap: () => setState(() {
                        selected = s.uuid;
                        value = kStr(s.kind == 'free' ? s.kg : s.total);
                      }),
                    );
                  }()
                : const SizedBox(),
          ),
      ]);
    }

    return hrow(key: const ValueKey('edit'), [
      w(1.4, NumPad(value, (x) => setState(() => value = x))),
      w(1, vcol([
        BigTitle('${names[sale.productUuid] ?? ''}  ${fmtShort(sale.deviceTime)}'),
        w(1, Readout(free ? T.kilo : T.total, value, true, onTap: () {})),
        w(1, Plain(T.back, size: 20, onTap: clear)),
        w(1, Plain(T.undo, size: 20, onTap: () {
          guard(context, repo.undoSale(sale));
          clear();
        })),
        w(1.5, Plain(T.save, enabled: v != null && v > 0, size: 24, onTap: () {
          final n = v;
          if (n == null) return;
          final total = free ? 0.0 : n;
          final kg = switch (sale.kind) {
            'free' => n,
            'paid' => r3(n / sale.pricePerKg),
            _ => sale.kg,
          };
          guard(context, repo.editSale(sale, total, kg));
          clear();
        })),
      ])),
    ]);
  }
}

class DebugScreen extends StatefulWidget {
  const DebugScreen(this.c, {super.key});
  final Ctx c;
  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  String result = '';

  Future<String> _test() async {
    final neon = widget.c.deps.neon;
    try {
      if (!neon.configured) return 'NEON_SQL_URL empty (secrets.json)';
      const t = SyncTable('debug_pings', [('uuid', 'uuid', 'u'), ('note', 'note', 's'), ('device_time', 'device_time', 't')]);
      final now = DateTime.now().millisecondsSinceEpoch;
      final q = neonQuery(t, {'uuid': newId(), 'note': 'test', 'device_time': now}, now);
      final (code, body) = await neon.post([q]);
      return 'HTTP $code\n$body';
    } catch (e) {
      return 'ERROR: ${e.runtimeType}: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return hrow([
      w(1, vcol([
        w(1, Plain(T.back, onTap: c.back)),
        w(1, Plain(T.sendAll, onTap: () async {
          setState(() => result = '...');
          final r = await c.deps.push();
          if (mounted) setState(() => result = r ?? 'OK');
        })),
        w(1, Plain(T.sendTest, onTap: () async {
          setState(() => result = '...');
          final r = await _test();
          if (mounted) setState(() => result = r);
        })),
      ])),
      w(2, SingleChildScrollView(child: Text(result, style: const TextStyle(fontSize: 18, color: Colors.black)))),
    ]);
  }
}
