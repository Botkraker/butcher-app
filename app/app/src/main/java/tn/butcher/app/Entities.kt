package tn.butcher.app

import androidx.room.Entity
import androidx.room.PrimaryKey

// Append-only rows. Client UUID is the primary key. deviceTime is epoch ms.
// "synced" is the only field that changes after insert (local upload marker).

@Entity(tableName = "product_events")
data class ProductEvent(
    @PrimaryKey val uuid: String,
    val productUuid: String,
    val name: String,
    val kind: String, // create | price | hide
    val pricePerKg: Double?,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "supplier_events")
data class SupplierEvent(
    @PrimaryKey val uuid: String,
    val supplierUuid: String,
    val name: String,
    val kind: String, // create | hide
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "sales")
data class Sale(
    @PrimaryKey val uuid: String,
    val productUuid: String,
    val total: Double,
    val pricePerKg: Double,
    val kg: Double,
    val kind: String, // paid | discount | free
    val credit: Boolean,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "voids")
data class Void(
    @PrimaryKey val uuid: String,
    val targetTable: String,
    val targetUuid: String,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "carcasses")
data class Carcass(
    @PrimaryKey val uuid: String,
    val supplierUuid: String?,
    val kgBought: Double,
    val cost: Double,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "waste")
data class Waste(
    @PrimaryKey val uuid: String,
    val carcassUuid: String,
    val kg: Double,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "closings")
data class Closing(
    @PrimaryKey val uuid: String,
    val cashCounted: Double,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "cash_moves")
data class CashMove(
    @PrimaryKey val uuid: String,
    val amount: Double, // positive in, negative out
    val reason: String,
    val deviceTime: Long,
    val synced: Boolean = false,
)

@Entity(tableName = "stock_counts")
data class StockCount(
    @PrimaryKey val uuid: String,
    val productUuid: String,
    val kg: Double,
    val deviceTime: Long,
    val synced: Boolean = false,
)
