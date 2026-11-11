import 'package:app/logic.dart';
import 'package:app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseNum reads the pad like Kotlin toDoubleOrNull', () {
    expect(parseNum('25'), 25.0);
    expect(parseNum('12.5'), 12.5);
    expect(parseNum('12,5'), 12.5);
    expect(parseNum(' 7 '), 7.0);
    expect(parseNum('5.'), 5.0);
    expect(parseNum('.5'), 0.5);
    expect(parseNum(''), isNull);
    expect(parseNum('.'), isNull);
    expect(parseNum('1.2.3'), isNull);
  });

  test('r3 rounds half to even like kotlin.math.round', () {
    expect(rint(2.5), 2.0);
    expect(rint(3.5), 4.0);
    expect(rint(-2.5), -2.0);
    expect(rint(2.4), 2.0);
    expect(rint(2.6), 3.0);
    expect(r3(0.0005), 0.0); // 0.5 -> 0 (even)
    expect(r3(10 / 3), 3.333);
    expect(r3(30 / 28), 1.071);
    expect(r3(35 * 28.5), 997.5);
  });

  test('fmtNum shows millimes without trailing zeros', () {
    expect(fmtNum(25.0), '25');
    expect(fmtNum(12.5), '12.5');
    expect(fmtNum(1.071), '1.071');
    expect(fmtNum(100), '100');
    expect(fmtNum(0), '0');
    expect(fmtNum(-0.0), '0');
    expect(fmtNum(-12.25), '-12.25');
    expect(fmtNum(1 / 3), '0.333');
  });

  test('kStr matches Kotlin Double.toString for normal prices', () {
    expect(kStr(25.0), '25.0');
    expect(kStr(12.5), '12.5');
  });

  test('cleanName trims and joins spaces', () {
    expect(cleanName('  علي   بن  صالح '), 'علي بن صالح');
  });

  test('foldProducts applies create, price and hide in order', () {
    final ev = [
      ProductEvent('e1', 'p1', 'علوش', 'create', 0.0, 1),
      ProductEvent('e2', 'p2', 'فيلي', 'create', 0.0, 2),
      ProductEvent('e3', 'p1', 'علوش', 'price', 38.0, 3),
      ProductEvent('e4', 'p2', 'فيلي', 'hide', null, 4),
      ProductEvent('e5', 'p9', 'x', 'price', 5.0, 5), // price before create: ignored
    ];
    final p = foldProducts(ev);
    expect(p.map((x) => x.uuid), ['p1', 'p2']);
    expect(p[0].price, 38.0);
    expect(p[1].hidden, true);
  });

  CreditEvent ce(String id, String who, double a, String kind, {String? sale}) => CreditEvent(id, who, a, kind, sale, 1);

  test('liveCredits drops voided rows and rows of voided sales', () {
    final ev = [ce('c1', 'علي', 10, 'debt'), ce('c2', 'علي', 5, 'debt', sale: 's1'), ce('c3', 'علي', 3, 'pay')];
    expect(liveCredits(ev, {'c3'}).map((e) => e.uuid), ['c1', 'c2']);
    expect(liveCredits(ev, {'s1'}).map((e) => e.uuid), ['c1', 'c3']);
  });

  test('balances: debts minus payments, per person', () {
    final b = balances([ce('1', 'a', 10, 'debt'), ce('2', 'b', 4, 'debt'), ce('3', 'a', 2.5, 'pay')]);
    expect(b, {'a': 7.5, 'b': 4.0});
  });

  test('canonical reuses the saved spelling', () {
    expect(canonical('  ali ', ['Ali', 'Salah']), 'Ali');
    expect(canonical('محمد  علي', ['محمد علي']), 'محمد علي');
    expect(canonical('new', ['Ali']), 'new');
  });

  test('peopleByRecent keeps the first time each name appears', () {
    expect(peopleByRecent([ce('1', 'b', 1, 'debt'), ce('2', 'a', 1, 'debt'), ce('3', 'b', 1, 'debt')]), ['b', 'a']);
  });

  ProductView pv(String id) => ProductView(id, id, 1, false);

  test('sortProducts follows the saved order, new ones last', () {
    final s = sortProducts([pv('a'), pv('b'), pv('c'), pv('d')], ['c', 'a']);
    expect(s.map((p) => p.uuid), ['c', 'a', 'b', 'd']);
  });

  test('moveTo puts the item in the target place', () {
    expect(moveTo(['a', 'b', 'c', 'd'], 'a', 'c'), ['b', 'c', 'a', 'd']);
    expect(moveTo(['a', 'b', 'c', 'd'], 'd', 'a'), ['d', 'a', 'b', 'c']);
    expect(moveTo(['a', 'b'], 'a', 'a'), ['a', 'b']);
    expect(moveTo(['a', 'b'], 'x', 'a'), ['a', 'b']);
  });

  test('sortedByDesc is stable like Kotlin', () {
    final l = [('a', 1.0), ('b', 2.0), ('c', 1.0), ('d', 2.0)];
    expect(sortedByDesc(l, (e) => e.$2).map((e) => e.$1), ['b', 'd', 'a', 'c']);
  });

  test('startOfDay is local midnight, days back', () {
    final now = DateTime(2026, 3, 1, 15, 30);
    expect(DateTime.fromMillisecondsSinceEpoch(startOfDay(1, now)), DateTime(2026, 3, 1));
    expect(DateTime.fromMillisecondsSinceEpoch(startOfDay(3, now)), DateTime(2026, 2, 27));
  });

  test('supplierOwed: costs minus money given', () {
    final p = [Purchase('1', 'x', 30, 20, 600, 500, 1), Purchase('2', '', 0, 0, 0, 50, 2)];
    expect(supplierOwed(p), 50.0);
  });

  test('newId looks like a v4 UUID', () {
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(newId()), true);
  });
}
