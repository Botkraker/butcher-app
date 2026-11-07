package tn.butcher.app

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Column types: u uuid, t epoch-ms time, r number, s text, b boolean. */
class SyncTable(
    val name: String,
    val cols: List<Pair<String, Char>>,
    val load: suspend (AppDao) -> List<Pair<String, List<Any?>>>,
    val mark: suspend (AppDao, List<String>) -> Unit,
)

object Neon {
    private const val SENT = "sent_device_time"

    val tables: List<SyncTable> = listOf(
        SyncTable("product_events",
            listOf("uuid" to 'u', "product_uuid" to 'u', "name" to 's', "kind" to 's', "price_per_kg" to 'r', "device_time" to 't'),
            { d -> d.unsentProductEvents().map { it.uuid to listOf(it.uuid, it.productUuid, it.name, it.kind, it.pricePerKg, it.deviceTime) } },
            { d, ids -> d.markProductEvents(ids) }),
        SyncTable("supplier_events",
            listOf("uuid" to 'u', "supplier_uuid" to 'u', "name" to 's', "kind" to 's', "device_time" to 't'),
            { d -> d.unsentSupplierEvents().map { it.uuid to listOf(it.uuid, it.supplierUuid, it.name, it.kind, it.deviceTime) } },
            { d, ids -> d.markSupplierEvents(ids) }),
        SyncTable("sales",
            listOf("uuid" to 'u', "product_uuid" to 'u', "total" to 'r', "price_per_kg" to 'r', "kg" to 'r', "kind" to 's', "credit" to 'b', "device_time" to 't'),
            { d -> d.unsentSales().map { it.uuid to listOf(it.uuid, it.productUuid, it.total, it.pricePerKg, it.kg, it.kind, it.credit, it.deviceTime) } },
            { d, ids -> d.markSales(ids) }),
        SyncTable("voids",
            listOf("uuid" to 'u', "target_table" to 's', "target_uuid" to 'u', "device_time" to 't'),
            { d -> d.unsentVoids().map { it.uuid to listOf(it.uuid, it.targetTable, it.targetUuid, it.deviceTime) } },
            { d, ids -> d.markVoids(ids) }),
        SyncTable("carcasses",
            listOf("uuid" to 'u', "supplier_uuid" to 'u', "kg_bought" to 'r', "cost" to 'r', "device_time" to 't'),
            { d -> d.unsentCarcasses().map { it.uuid to listOf(it.uuid, it.supplierUuid, it.kgBought, it.cost, it.deviceTime) } },
            { d, ids -> d.markCarcasses(ids) }),
        SyncTable("waste",
            listOf("uuid" to 'u', "carcass_uuid" to 'u', "kg" to 'r', "device_time" to 't'),
            { d -> d.unsentWaste().map { it.uuid to listOf(it.uuid, it.carcassUuid, it.kg, it.deviceTime) } },
            { d, ids -> d.markWaste(ids) }),
        SyncTable("closings",
            listOf("uuid" to 'u', "cash_counted" to 'r', "device_time" to 't'),
            { d -> d.unsentClosings().map { it.uuid to listOf(it.uuid, it.cashCounted, it.deviceTime) } },
            { d, ids -> d.markClosings(ids) }),
        SyncTable("cash_moves",
            listOf("uuid" to 'u', "amount" to 'r', "reason" to 's', "device_time" to 't'),
            { d -> d.unsentCashMoves().map { it.uuid to listOf(it.uuid, it.amount, it.reason, it.deviceTime) } },
            { d, ids -> d.markCashMoves(ids) }),
        SyncTable("stock_counts",
            listOf("uuid" to 'u', "product_uuid" to 'u', "kg" to 'r', "device_time" to 't'),
            { d -> d.unsentStockCounts().map { it.uuid to listOf(it.uuid, it.productUuid, it.kg, it.deviceTime) } },
            { d, ids -> d.markStockCounts(ids) }),
    )

    /** One statement: bare INSERT ... ON CONFLICT DO NOTHING (no target, no RETURNING). */
    fun query(table: String, cols: List<Pair<String, Char>>, values: List<Any?>, sentAt: Long): JSONObject {
        val names = cols.map { it.first } + SENT
        val marks = cols.mapIndexed { i, c -> cast(c.second, i + 1) } + cast('t', cols.size + 1)
        val params = JSONArray()
        (values + sentAt).forEach { params.put(it?.toString() ?: JSONObject.NULL) }
        return JSONObject()
            .put("query", "INSERT INTO $table (${names.joinToString()}) VALUES (${marks.joinToString()}) ON CONFLICT DO NOTHING")
            .put("params", params)
    }

    private fun cast(t: Char, i: Int) = when (t) {
        'u' -> "\$$i::uuid"
        't' -> "to_timestamp(\$$i::double precision / 1000)"
        'r' -> "\$$i::double precision"
        'b' -> "\$$i::boolean"
        else -> "\$$i::text"
    }

    /** Sends statements as one batch (one transaction). Returns HTTP code and body. */
    fun post(queries: List<JSONObject>): Pair<Int, String> {
        val c = URL(BuildConfig.NEON_SQL_URL).openConnection() as HttpURLConnection
        try {
            c.requestMethod = "POST"
            c.connectTimeout = 15000
            c.readTimeout = 30000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("Neon-Connection-String", BuildConfig.NEON_CONNECTION_STRING)
            val body = JSONObject().put("queries", JSONArray(queries)).toString()
            c.outputStream.use { it.write(body.toByteArray()) }
            val code = c.responseCode
            val stream = if (code < 400) c.inputStream else c.errorStream
            return code to (stream?.bufferedReader()?.use { it.readText() } ?: "")
        } finally {
            c.disconnect()
        }
    }
}

/** Sends every unsent row. Returns null when all went up, else the error text. */
suspend fun pushAll(ctx: Context): String? {
    val dao = AppDb.get(ctx).dao()
    try {
        for (t in Neon.tables) {
            while (true) {
                val rows = t.load(dao)
                if (rows.isEmpty()) break
                val now = System.currentTimeMillis()
                val qs = rows.map { Neon.query(t.name, t.cols, it.second, now) }
                val (code, body) = Neon.post(qs)
                if (code != 200) return "${t.name}: HTTP $code $body"
                t.mark(dao, rows.map { it.first })
                Prefs.setLastSync(ctx, System.currentTimeMillis())
            }
        }
    } catch (e: IOException) {
        return "${e.javaClass.simpleName}: ${e.message}"
    }
    return null
}

class SyncWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        if (BuildConfig.NEON_SQL_URL.isBlank()) return Result.failure()
        return if (pushAll(applicationContext) == null) Result.success() else Result.retry()
    }

    companion object {
        fun enqueue(ctx: Context) {
            val req = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(ctx).enqueueUniqueWork("sync", ExistingWorkPolicy.REPLACE, req)
        }
    }
}

object Prefs {
    private fun p(ctx: Context) = ctx.getSharedPreferences("butcher", Context.MODE_PRIVATE)
    fun lastSync(ctx: Context): Long = p(ctx).getLong("last_sync", 0L)
    fun setLastSync(ctx: Context, t: Long) = p(ctx).edit().putLong("last_sync", t).apply()
}
