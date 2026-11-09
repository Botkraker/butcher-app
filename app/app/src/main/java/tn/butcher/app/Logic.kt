package tn.butcher.app

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Calendar
import kotlin.math.round

// Plain functions, no Android UI. Kept apart so they are easy to check.

fun cleanName(s: String): String = s.trim().replace(Regex("\\s+"), " ")

/** Rounds to millimes (3 decimals). */
fun r3(d: Double): Double = round(d * 1000) / 1000

/** 25.0 -> "25", 12.5 -> "12.5", 1.2345 -> "1.235". */
fun show(d: Double): String =
    BigDecimal.valueOf(r3(d)).setScale(3, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()

/** Midnight today, minus (days - 1) days. days = 1 means today only. */
fun startOfDay(days: Int): Long = Calendar.getInstance().apply {
    set(Calendar.HOUR_OF_DAY, 0)
    set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0)
    set(Calendar.MILLISECOND, 0)
    add(Calendar.DAY_OF_MONTH, -(days - 1))
}.timeInMillis

/** Credit rows that still count: not voided, and their sale (if any) not voided. */
fun liveCredits(events: List<CreditEvent>, voided: Set<String>): List<CreditEvent> =
    events.filter { it.uuid !in voided && (it.saleUuid == null || it.saleUuid !in voided) }

/** What each person still owes: debts minus payments. */
fun balances(live: List<CreditEvent>): Map<String, Double> =
    live.groupBy { it.person }.mapValues { (_, l) ->
        r3(l.sumOf { if (it.kind == "pay") -it.amount else it.amount })
    }

/** Reuses the spelling already saved when only case or spaces differ, so one person keeps one balance. */
fun canonical(name: String, known: List<String>): String {
    val n = cleanName(name)
    return known.firstOrNull { it.equals(n, ignoreCase = true) } ?: n
}

/** Puts products in the saved order. Products not in it (new ones) go at the end, oldest first. */
fun sortProducts(products: List<ProductView>, order: List<String>): List<ProductView> {
    val idx = order.withIndex().associate { it.value to it.index }
    return products.withIndex()
        .sortedWith(compareBy({ idx[it.value.uuid] ?: Int.MAX_VALUE }, { it.index }))
        .map { it.value }
}

/** Moves item to the place of target. The others shift by one. */
fun moveTo(ids: List<String>, item: String, target: String): List<String> {
    val from = ids.indexOf(item)
    val to = ids.indexOf(target)
    if (from < 0 || to < 0 || from == to) return ids
    val m = ids.toMutableList()
    m.removeAt(from)
    m.add(to, item)
    return m
}

/** Names, most recent first. Events come newest first from the DAO. */
fun peopleByRecent(events: List<CreditEvent>): List<String> = events.map { it.person }.distinct()

/** What the butcher still owes the supplier: all costs minus all money given. */
fun supplierOwed(purchases: List<Purchase>): Double = r3(purchases.sumOf { it.cost - it.paid })
