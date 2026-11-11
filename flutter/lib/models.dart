// Append-only rows. Client UUID is the primary key. deviceTime is epoch ms.
// "synced" is the only field that changes after insert (local upload marker).
// Column names are the ones the Kotlin app (Room) created, so the old database file still works.

double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
bool _b(Object? v) => v == 1 || v == true;

class ProductEvent {
  ProductEvent(this.uuid, this.productUuid, this.name, this.kind, this.pricePerKg, this.deviceTime, {this.synced = false});
  final String uuid, productUuid, name;
  final String kind; // create | price | hide
  final double? pricePerKg;
  final int deviceTime;
  final bool synced;

  factory ProductEvent.fromMap(Map<String, Object?> m) => ProductEvent(
      m['uuid'] as String, m['productUuid'] as String, m['name'] as String, m['kind'] as String,
      _dn(m['pricePerKg']), m['deviceTime'] as int, synced: _b(m['synced']));
  Map<String, Object?> toMap() => {
        'uuid': uuid, 'productUuid': productUuid, 'name': name, 'kind': kind,
        'pricePerKg': pricePerKg, 'deviceTime': deviceTime, 'synced': synced ? 1 : 0,
      };
}

class Sale {
  Sale(this.uuid, this.productUuid, this.total, this.pricePerKg, this.kg, this.kind, this.credit, this.deviceTime, {this.synced = false});
  final String uuid, productUuid;
  final double total, pricePerKg, kg;
  final String kind; // paid | discount | free (free is old, no longer created)
  final bool credit;
  final int deviceTime;
  final bool synced;

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
      m['uuid'] as String, m['productUuid'] as String, _d(m['total']), _d(m['pricePerKg']), _d(m['kg']),
      m['kind'] as String, _b(m['credit']), m['deviceTime'] as int, synced: _b(m['synced']));
  Map<String, Object?> toMap() => {
        'uuid': uuid, 'productUuid': productUuid, 'total': total, 'pricePerKg': pricePerKg, 'kg': kg,
        'kind': kind, 'credit': credit ? 1 : 0, 'deviceTime': deviceTime, 'synced': synced ? 1 : 0,
      };
}

/// A cancel row. targetTable + targetUuid name the row it cancels.
class VoidRow {
  VoidRow(this.uuid, this.targetTable, this.targetUuid, this.deviceTime, {this.synced = false});
  final String uuid, targetTable, targetUuid;
  final int deviceTime;
  final bool synced;

  factory VoidRow.fromMap(Map<String, Object?> m) => VoidRow(
      m['uuid'] as String, m['targetTable'] as String, m['targetUuid'] as String, m['deviceTime'] as int,
      synced: _b(m['synced']));
  Map<String, Object?> toMap() => {
        'uuid': uuid, 'targetTable': targetTable, 'targetUuid': targetUuid, 'deviceTime': deviceTime,
        'synced': synced ? 1 : 0,
      };
}

class CashMove {
  CashMove(this.uuid, this.amount, this.reason, this.deviceTime, {this.synced = false});
  final String uuid;
  final double amount; // positive in, negative out
  final String reason;
  final int deviceTime;
  final bool synced;

  factory CashMove.fromMap(Map<String, Object?> m) => CashMove(
      m['uuid'] as String, _d(m['amount']), m['reason'] as String, m['deviceTime'] as int, synced: _b(m['synced']));
  Map<String, Object?> toMap() =>
      {'uuid': uuid, 'amount': amount, 'reason': reason, 'deviceTime': deviceTime, 'synced': synced ? 1 : 0};
}

/// A customer debt (debt) or a payment back (pay). saleUuid links a credit sale.
class CreditEvent {
  CreditEvent(this.uuid, this.person, this.amount, this.kind, this.saleUuid, this.deviceTime, {this.synced = false});
  final String uuid, person;
  final double amount;
  final String kind; // debt | pay
  final String? saleUuid;
  final int deviceTime;
  final bool synced;

  factory CreditEvent.fromMap(Map<String, Object?> m) => CreditEvent(
      m['uuid'] as String, m['person'] as String, _d(m['amount']), m['kind'] as String, m['saleUuid'] as String?,
      m['deviceTime'] as int, synced: _b(m['synced']));
  Map<String, Object?> toMap() => {
        'uuid': uuid, 'person': person, 'amount': amount, 'kind': kind, 'saleUuid': saleUuid,
        'deviceTime': deviceTime, 'synced': synced ? 1 : 0,
      };
}

/// A supplier purchase. item is empty for a payment only. cost = kg * pricePerKg.
class Purchase {
  Purchase(this.uuid, this.item, this.kg, this.pricePerKg, this.cost, this.paid, this.deviceTime, {this.synced = false});
  final String uuid, item;
  final double kg, pricePerKg, cost, paid;
  final int deviceTime;
  final bool synced;

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
      m['uuid'] as String, m['item'] as String, _d(m['kg']), _d(m['pricePerKg']), _d(m['cost']), _d(m['paid']),
      m['deviceTime'] as int, synced: _b(m['synced']));
  Map<String, Object?> toMap() => {
        'uuid': uuid, 'item': item, 'kg': kg, 'pricePerKg': pricePerKg, 'cost': cost, 'paid': paid,
        'deviceTime': deviceTime, 'synced': synced ? 1 : 0,
      };
}

class ProductView {
  const ProductView(this.uuid, this.name, this.price, this.hidden);
  final String uuid, name;
  final double price;
  final bool hidden;
  ProductView copyWith({double? price, bool? hidden}) => ProductView(uuid, name, price ?? this.price, hidden ?? this.hidden);
}
