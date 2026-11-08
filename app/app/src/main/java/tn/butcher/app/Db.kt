package tn.butcher.app

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import kotlinx.coroutines.flow.Flow

@Dao
interface AppDao {
    // Inserts only. No update or delete of data rows.
    @Insert suspend fun insert(r: ProductEvent)
    @Insert suspend fun insert(r: SupplierEvent)
    @Insert suspend fun insert(r: Sale)
    @Insert suspend fun insert(r: Void)
    @Insert suspend fun insert(r: Carcass)
    @Insert suspend fun insert(r: Waste)
    @Insert suspend fun insert(r: Closing)
    @Insert suspend fun insert(r: CashMove)
    @Insert suspend fun insert(r: StockCount)
    @Insert suspend fun insert(r: CreditEvent)
    @Insert suspend fun insert(r: Purchase)

    @Query("SELECT * FROM product_events ORDER BY deviceTime, rowid")
    fun productEvents(): Flow<List<ProductEvent>>

    @Query(
        "SELECT * FROM sales WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'sales') " +
            "ORDER BY deviceTime DESC LIMIT 1"
    )
    fun lastLiveSale(): Flow<Sale?>

    @Query(
        "SELECT * FROM sales WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'sales') " +
            "ORDER BY deviceTime DESC, rowid DESC LIMIT 500"
    )
    fun liveSales(): Flow<List<Sale>>

    @Query(
        "SELECT * FROM sales WHERE deviceTime >= :since AND uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'sales')"
    )
    fun salesSince(since: Long): Flow<List<Sale>>

    @Query("SELECT targetUuid FROM voids")
    fun voidedIds(): Flow<List<String>>

    @Query("SELECT * FROM credit_events ORDER BY deviceTime DESC, rowid DESC")
    fun creditEvents(): Flow<List<CreditEvent>>

    @Query("SELECT * FROM credit_events WHERE saleUuid = :saleUuid AND uuid NOT IN (SELECT targetUuid FROM voids) LIMIT 1")
    suspend fun creditForSale(saleUuid: String): CreditEvent?

    @Query(
        "SELECT * FROM purchases WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'purchases') " +
            "ORDER BY deviceTime DESC, rowid DESC"
    )
    fun livePurchases(): Flow<List<Purchase>>

    @Query(
        "SELECT * FROM cash_moves WHERE uuid NOT IN (SELECT targetUuid FROM voids WHERE targetTable = 'cash_moves') " +
            "ORDER BY deviceTime DESC, rowid DESC"
    )
    fun liveCashMoves(): Flow<List<CashMove>>

    // Unsent rows, 100 at a time.
    @Query("SELECT * FROM product_events WHERE synced = 0 LIMIT 100") suspend fun unsentProductEvents(): List<ProductEvent>
    @Query("SELECT * FROM supplier_events WHERE synced = 0 LIMIT 100") suspend fun unsentSupplierEvents(): List<SupplierEvent>
    @Query("SELECT * FROM sales WHERE synced = 0 LIMIT 100") suspend fun unsentSales(): List<Sale>
    @Query("SELECT * FROM voids WHERE synced = 0 LIMIT 100") suspend fun unsentVoids(): List<Void>
    @Query("SELECT * FROM carcasses WHERE synced = 0 LIMIT 100") suspend fun unsentCarcasses(): List<Carcass>
    @Query("SELECT * FROM waste WHERE synced = 0 LIMIT 100") suspend fun unsentWaste(): List<Waste>
    @Query("SELECT * FROM closings WHERE synced = 0 LIMIT 100") suspend fun unsentClosings(): List<Closing>
    @Query("SELECT * FROM cash_moves WHERE synced = 0 LIMIT 100") suspend fun unsentCashMoves(): List<CashMove>
    @Query("SELECT * FROM stock_counts WHERE synced = 0 LIMIT 100") suspend fun unsentStockCounts(): List<StockCount>
    @Query("SELECT * FROM credit_events WHERE synced = 0 LIMIT 100") suspend fun unsentCreditEvents(): List<CreditEvent>
    @Query("SELECT * FROM purchases WHERE synced = 0 LIMIT 100") suspend fun unsentPurchases(): List<Purchase>

    // Upload marker only.
    @Query("UPDATE product_events SET synced = 1 WHERE uuid IN (:ids)") suspend fun markProductEvents(ids: List<String>)
    @Query("UPDATE supplier_events SET synced = 1 WHERE uuid IN (:ids)") suspend fun markSupplierEvents(ids: List<String>)
    @Query("UPDATE sales SET synced = 1 WHERE uuid IN (:ids)") suspend fun markSales(ids: List<String>)
    @Query("UPDATE voids SET synced = 1 WHERE uuid IN (:ids)") suspend fun markVoids(ids: List<String>)
    @Query("UPDATE carcasses SET synced = 1 WHERE uuid IN (:ids)") suspend fun markCarcasses(ids: List<String>)
    @Query("UPDATE waste SET synced = 1 WHERE uuid IN (:ids)") suspend fun markWaste(ids: List<String>)
    @Query("UPDATE closings SET synced = 1 WHERE uuid IN (:ids)") suspend fun markClosings(ids: List<String>)
    @Query("UPDATE cash_moves SET synced = 1 WHERE uuid IN (:ids)") suspend fun markCashMoves(ids: List<String>)
    @Query("UPDATE stock_counts SET synced = 1 WHERE uuid IN (:ids)") suspend fun markStockCounts(ids: List<String>)
    @Query("UPDATE credit_events SET synced = 1 WHERE uuid IN (:ids)") suspend fun markCreditEvents(ids: List<String>)
    @Query("UPDATE purchases SET synced = 1 WHERE uuid IN (:ids)") suspend fun markPurchases(ids: List<String>)
}

@Database(
    entities = [
        ProductEvent::class, SupplierEvent::class, Sale::class, Void::class, Carcass::class,
        Waste::class, Closing::class, CashMove::class, StockCount::class, CreditEvent::class, Purchase::class,
    ],
    version = 2,
    exportSchema = false,
)
abstract class AppDb : RoomDatabase() {
    abstract fun dao(): AppDao

    companion object {
        @Volatile private var inst: AppDb? = null
        fun get(ctx: Context): AppDb = inst ?: synchronized(this) {
            inst ?: Room.databaseBuilder(ctx.applicationContext, AppDb::class.java, "butcher.db")
                .addMigrations(MIGRATION_1_2)
                .build().also { inst = it }
        }
    }
}

/**
 * v1 -> v2 adds two tables and changes nothing old, so the phone keeps its data.
 * The SQL must match what Room expects for the entities, or Room stops at start.
 * Never use fallbackToDestructiveMigration: it deletes the butcher's data.
 */
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `credit_events` (`uuid` TEXT NOT NULL, `person` TEXT NOT NULL, " +
                "`amount` REAL NOT NULL, `kind` TEXT NOT NULL, `saleUuid` TEXT, `deviceTime` INTEGER NOT NULL, " +
                "`synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))"
        )
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS `purchases` (`uuid` TEXT NOT NULL, `item` TEXT NOT NULL, `kg` REAL NOT NULL, " +
                "`pricePerKg` REAL NOT NULL, `cost` REAL NOT NULL, `paid` REAL NOT NULL, `deviceTime` INTEGER NOT NULL, " +
                "`synced` INTEGER NOT NULL, PRIMARY KEY(`uuid`))"
        )
    }
}
