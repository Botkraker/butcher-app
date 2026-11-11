import 'dart:collection';
import 'dart:math';

import 'models.dart';

// Plain functions, no UI. Kept apart so they are easy to test.

final _rand = Random.secure();

/// Random UUID v4, like java.util.UUID.randomUUID().
String newId() {
  final b = List<int>.generate(16, (_) => _rand.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Number typed on the pad. Comma counts as a dot. Null when it is not a number.
double? parseNum(String s) {
  var t = s.trim().replaceAll(',', '.');
  if (t.endsWith('.') && t.length > 1) t = '${t}0'; // "5." is 5, as in Kotlin
  return double.tryParse(t);
}

/// Rounds half to even, like kotlin.math.round (Math.rint).
double rint(double x) {
  final f = x.floorToDouble();
  final diff = x - f;
  if (diff < 0.5) return f;
  if (diff > 0.5) return f + 1;
  return f % 2 == 0 ? f : f + 1;
}

/// Rounds to millimes (3 decimals).
double r3(double d) => rint(d * 1000) / 1000;

/// 25.0 -> "25", 12.5 -> "12.5", 1.2345 -> "1.234" (millimes, half to even first).
String fmtNum(double d) {
  final v = r3(d);
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// Kotlin Double.toString for the values this app shows (25.0, 12.5).
String kStr(double d) => d.toString();

String cleanName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Midnight today, minus (days - 1) days. days = 1 means today only.
int startOfDay(int days, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day - (days - 1)).millisecondsSinceEpoch;
}

String _p2(int v) => v.toString().padLeft(2, '0');

/// yyyy-MM-dd HH:mm, phone time.
String fmtDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
}

/// dd/MM HH:mm, phone time.
String fmtShort(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_p2(d.day)}/${_p2(d.month)} ${_p2(d.hour)}:${_p2(d.minute)}';
}

/// Kotlin's sortedByDescending: stable, so equal keys keep their order.
List<E> sortedByDesc<E>(List<E> l, double Function(E) key) {
  final idx = List.generate(l.length, (i) => i);
  idx.sort((a, b) {
    final c = key(l[b]).compareTo(key(l[a]));
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) l[i]];
}

List<E> distinct<E>(Iterable<E> l) => LinkedHashSet<E>.of(l).toList();

List<ProductView> foldProducts(List<ProductEvent> events) {
  final m = <String, ProductView>{}; // insertion order, like LinkedHashMap
  for (final e in events) {
    final cur = m[e.productUuid];
    switch (e.kind) {
      case 'create':
        m[e.productUuid] = ProductView(e.productUuid, e.name, e.pricePerKg ?? 0.0, false);
      case 'price':
        if (cur != null && e.pricePerKg != null) m[e.productUuid] = cur.copyWith(price: e.pricePerKg);
      case 'hide':
        if (cur != null) m[e.productUuid] = cur.copyWith(hidden: true);
    }
  }
  return m.values.toList();
}

/// Credit rows that still count: not voided, and their sale (if any) not voided.
List<CreditEvent> liveCredits(List<CreditEvent> events, Set<String> voided) => events
    .where((e) => !voided.contains(e.uuid) && (e.saleUuid == null || !voided.contains(e.saleUuid)))
    .toList();

/// What each person still owes: debts minus payments.
Map<String, double> balances(List<CreditEvent> live) {
  final sums = <String, List<CreditEvent>>{};
  for (final e in live) {
    sums.putIfAbsent(e.person, () => []).add(e);
  }
  return sums.map((p, l) {
    var s = 0.0;
    for (final e in l) {
      s += e.kind == 'pay' ? -e.amount : e.amount;
    }
    return MapEntry(p, r3(s));
  });
}

/// Reuses the spelling already saved when only case or spaces differ, so one person keeps one balance.
String canonical(String name, List<String> known) {
  final n = cleanName(name);
  for (final k in known) {
    if (k.toLowerCase() == n.toLowerCase()) return k;
  }
  return n;
}

/// Puts products in the saved order. Products not in it (new ones) go at the end, oldest first.
List<ProductView> sortProducts(List<ProductView> products, List<String> order) {
  final idx = <String, int>{};
  for (var i = 0; i < order.length; i++) {
    idx[order[i]] = i;
  }
  const big = 1 << 30;
  final pos = List.generate(products.length, (i) => i);
  pos.sort((a, b) {
    final c = (idx[products[a].uuid] ?? big).compareTo(idx[products[b].uuid] ?? big);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in pos) products[i]];
}

/// Moves item to the place of target. The others shift by one.
List<String> moveTo(List<String> ids, String item, String target) {
  final from = ids.indexOf(item);
  final to = ids.indexOf(target);
  if (from < 0 || to < 0 || from == to) return ids;
  final m = List<String>.of(ids);
  m.removeAt(from);
  m.insert(to, item);
  return m;
}

/// Names, most recent first. Events come newest first from the database.
List<String> peopleByRecent(List<CreditEvent> events) => distinct(events.map((e) => e.person));

double _sum<E>(Iterable<E> l, double Function(E) f) {
  var s = 0.0;
  for (final e in l) {
    s += f(e);
  }
  return s;
}

double sumOf<E>(Iterable<E> l, double Function(E) f) => _sum(l, f);

/// What the butcher still owes the supplier: all costs minus all money given.
double supplierOwed(List<Purchase> purchases) => r3(_sum(purchases, (p) => p.cost - p.paid));
