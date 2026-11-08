package tn.butcher.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Credit: the list of people with what they owe, a new name, and the amount. */
@Composable
fun CreditScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val events by repo.creditEvents.collectAsState(emptyList())
    val voided = repo.voidedIds.collectAsState(emptyList()).value.toSet()
    val live = liveCredits(events, voided)
    val owed = balances(live)
    val people = peopleByRecent(events).sortedByDescending { owed[it] ?: 0.0 }
    var mode by rememberSaveable { mutableStateOf("list") }
    var person by rememberSaveable { mutableStateOf("") }
    var amount by rememberSaveable { mutableStateOf("") }
    val a = num(amount)
    val clear = { mode = "list"; person = ""; amount = "" }
    val save: (String) -> Unit = { kind ->
        val v = a
        val p = cleanName(person)
        if (v != null && v > 0 && p.isNotEmpty()) {
            scope.launch { withContext(Dispatchers.IO) { repo.addCredit(p, v, kind) } }
            clear()
        }
    }
    BackHandler(enabled = mode != "list") { clear() }

    when (mode) {
        "list" -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = back)
                Title(T.CREDITS, Modifier.weight(1f))
                // Only rows typed here. A credit sale is undone from بيعة or البيعات.
                val u = live.firstOrNull { it.saleUuid == null }
                val sign = if (u?.kind == "pay") "-" else "+"
                Small(if (u != null) "${T.UNDO} ${u.person} $sign${show(u.amount)}" else T.UNDO, enabled = u != null, width = 240) {
                    u?.let { scope.launch { withContext(Dispatchers.IO) { repo.void("credit_events", it.uuid) } } }
                }
                Small(T.NEW_PERSON, width = 150) { clear(); mode = "name" }
            }
            if (people.isEmpty()) Text(T.NO_CREDIT, fontSize = 24.sp, color = Color.Black)
            PagedGrid(people, 3, 4, Modifier.weight(1f).fillMaxWidth()) { p, m ->
                val b = owed[p] ?: 0.0
                Plain("$p\n${show(b)}", m, dim = b <= 0, size = 20.sp) { person = p; amount = ""; mode = "amount" }
            }
        }
        "name" -> NamePicker(
            T.NEW_PERSON, person, { person = it }, people,
            back = clear, action = T.NEXT, actionEnabled = cleanName(person).isNotEmpty(),
            onAction = { person = cleanName(person); mode = "amount" },
        )
        else -> Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            NumPad(Modifier.weight(1.4f).fillMaxSize(), amount) { amount = it }
            Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Title("$person: ${T.OWES} ${show(owed[person] ?: 0.0)}", Modifier.fillMaxWidth())
                Readout(T.AMOUNT, amount, true, Modifier.weight(1f).fillMaxWidth()) {}
                Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = clear)
                Plain(T.ADD_DEBT, Modifier.weight(1.2f).fillMaxWidth(), enabled = a != null && a > 0, size = 22.sp) { save("debt") }
                Plain(T.PAID_BACK, Modifier.weight(1.2f).fillMaxWidth(), enabled = a != null && a > 0, size = 22.sp) { save("pay") }
            }
        }
    }
}

/** Personal spending: the amount, then optional details. */
@Composable
fun SpendingScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val moves by repo.liveCashMoves.collectAsState(emptyList())
    val spends = moves.filter { it.amount < 0 }
    var mode by rememberSaveable { mutableStateOf("amount") }
    var amount by rememberSaveable { mutableStateOf("") }
    var details by rememberSaveable { mutableStateOf("") }
    val a = num(amount)
    val today = startOfDay(1)
    val todaySum = r3(spends.filter { it.deviceTime >= today }.sumOf { -it.amount })
    val reasons = spends.map { it.reason }.filter { it.isNotBlank() }.distinct()
    val clear = { mode = "amount"; amount = ""; details = "" }
    BackHandler(enabled = mode != "amount") { mode = "amount" }

    if (mode == "details") {
        NamePicker(
            T.DETAILS, details, { details = it }, reasons,
            back = { mode = "amount" }, action = T.SAVE, actionEnabled = a != null && a > 0, appendVoice = true,
            onAction = {
                val v = a
                val d = cleanName(details)
                if (v != null && v > 0) {
                    scope.launch { withContext(Dispatchers.IO) { repo.addSpending(v, d) } }
                    clear()
                }
            },
        )
        return
    }

    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        NumPad(Modifier.weight(1.4f).fillMaxSize(), amount) { amount = it }
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title("${T.SPEND}: ${T.TODAY} ${show(todaySum)}", Modifier.fillMaxWidth())
            Readout(T.AMOUNT, amount, true, Modifier.weight(1f).fillMaxWidth()) {}
            Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = back)
            val u = spends.firstOrNull()
            Plain(if (u != null) "${T.UNDO} ${show(-u.amount)}" else T.UNDO, Modifier.weight(1f).fillMaxWidth(), enabled = u != null, size = 20.sp) {
                u?.let { scope.launch { withContext(Dispatchers.IO) { repo.void("cash_moves", it.uuid) } } }
            }
            Plain(T.NEXT, Modifier.weight(1.5f).fillMaxWidth(), enabled = a != null && a > 0, size = 24.sp) { mode = "details" }
        }
    }
}

/** Supplier purchase: the item (old items suggested), then kg, price per kg, and money given. */
@Composable
fun PurchaseScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val purchases by repo.livePurchases.collectAsState(emptyList())
    val items = purchases.map { it.item }.filter { it.isNotEmpty() }.distinct()
    val owed = supplierOwed(purchases)
    var mode by rememberSaveable { mutableStateOf("name") }
    var item by rememberSaveable { mutableStateOf("") }
    var kg by rememberSaveable { mutableStateOf("") }
    var price by rememberSaveable { mutableStateOf("") }
    var paid by rememberSaveable { mutableStateOf("") }
    var field by rememberSaveable { mutableStateOf("kg") }
    val clear = { mode = "name"; item = ""; kg = ""; price = ""; paid = ""; field = "kg" }
    // Fills the last kg and price used for this item. Newest purchase comes first.
    val openItem: (String) -> Unit = { name ->
        val n = cleanName(name)
        val last = purchases.firstOrNull { it.item.equals(n, ignoreCase = true) }
        item = last?.item ?: n
        kg = last?.let { show(it.kg) } ?: ""
        price = last?.let { show(it.pricePerKg) } ?: ""
        paid = ""
        field = "kg"
        mode = "nums"
    }
    BackHandler(enabled = mode != "name") { mode = "name" }

    if (mode == "name") {
        NamePicker(
            T.WHAT_BOUGHT, item, { item = it }, items,
            back = back, action = T.NEXT, actionEnabled = cleanName(item).isNotEmpty(),
            onAction = { openItem(item) }, onPick = openItem,
            extra = {
                val u = purchases.firstOrNull()
                Small(if (u != null) "${T.UNDO} ${u.item.ifEmpty { show(u.paid) }}" else T.UNDO, enabled = u != null, width = 150) {
                    u?.let { scope.launch { withContext(Dispatchers.IO) { repo.void("purchases", it.uuid) } } }
                }
                Small(T.PAY_ONLY, width = 120) {
                    item = ""; kg = ""; price = ""; paid = ""; field = "paid"; mode = "nums"
                }
            },
        )
        return
    }

    val payOnly = item.isEmpty()
    val k = num(kg)
    val p = num(price)
    val g = if (paid.isEmpty()) 0.0 else num(paid)
    val cost = if (!payOnly && k != null && p != null) r3(k * p) else 0.0
    val valid = g != null && g >= 0 &&
        (if (payOnly) g > 0 else k != null && k > 0 && p != null && p > 0)
    val current = when (field) { "price" -> price; "paid" -> paid; else -> kg }
    val set: (String) -> Unit = { v ->
        when (field) {
            "price" -> { price = v }
            "paid" -> { paid = v }
            else -> { kg = v }
        }
    }

    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        NumPad(Modifier.weight(1.4f).fillMaxSize(), current, set)
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title(if (payOnly) T.PAY_ONLY else item, Modifier.fillMaxWidth())
            if (!payOnly) {
                Readout(T.KILO, kg, field == "kg", Modifier.weight(1f).fillMaxWidth()) { field = "kg" }
                Readout(T.PRICE, price, field == "price", Modifier.weight(1f).fillMaxWidth()) { field = "price" }
            }
            Readout(T.GAVE, paid, field == "paid", Modifier.weight(1f).fillMaxWidth()) { field = "paid" }
            if (!payOnly) Text("${T.TOTAL}: ${show(cost)}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.Black, maxLines = 1)
            Text("${T.OWE_AFTER}: ${show(owed + cost - (g ?: 0.0))}", fontSize = 18.sp, color = Color.Black, maxLines = 1)
            Row(Modifier.weight(1.2f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Plain(T.BACK, Modifier.weight(1f).fillMaxHeight(), size = 20.sp) { mode = "name" }
                Plain(T.SAVE, Modifier.weight(1.4f).fillMaxHeight(), enabled = valid, size = 24.sp) {
                    if (valid) {
                        val i = item
                        val kv = k ?: 0.0
                        val pv = p ?: 0.0
                        val gv = g ?: 0.0
                        scope.launch { withContext(Dispatchers.IO) { repo.addPurchase(i, if (payOnly) 0.0 else kv, if (payOnly) 0.0 else pv, gv) } }
                        clear()
                    }
                }
            }
        }
    }
}

/** Placeholder dashboard: pick the days, see each product's kg and money, and the totals. */
@Composable
fun DashboardScreen(repo: Repo, back: () -> Unit) {
    var days by rememberSaveable { mutableStateOf(1) }
    val since = startOfDay(days)
    val sales by remember(since) { repo.salesSince(since) }.collectAsState(emptyList())
    val names = foldProducts(repo.productEvents.collectAsState(emptyList()).value).associate { it.uuid to it.name }
    val purchases = repo.livePurchases.collectAsState(emptyList()).value.filter { it.deviceTime >= since }
    val spends = repo.liveCashMoves.collectAsState(emptyList()).value.filter { it.deviceTime >= since && it.amount < 0 }
    val voided = repo.voidedIds.collectAsState(emptyList()).value.toSet()
    val credits = liveCredits(repo.creditEvents.collectAsState(emptyList()).value, voided).filter { it.deviceTime >= since }

    val rows = sales.groupBy { it.productUuid }
        .map { (id, l) -> Triple(names[id] ?: "?", r3(l.sumOf { it.kg }), r3(l.sumOf { it.total })) }
        .sortedByDescending { it.third }
    val sold = r3(sales.sumOf { it.total })
    val bought = r3(purchases.sumOf { it.cost })
    val gave = r3(purchases.sumOf { it.paid })
    val spent = r3(spends.sumOf { -it.amount })
    val newDebt = r3(credits.filter { it.kind == "debt" }.sumOf { it.amount })
    val paidBack = r3(credits.filter { it.kind == "pay" }.sumOf { it.amount })
    val totals = listOf(
        T.SOLD to sold, T.CREDIT_GIVEN to newDebt, T.CREDIT_BACK to paidBack,
        T.BOUGHT to bought, T.GAVE to gave, T.SPEND to spent, T.NET to r3(sold - bought - spent),
    )

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Bar {
            Small(T.BACK, onClick = back)
            Title(T.DASH, Modifier.weight(1f))
            listOf(1 to T.TODAY, 3 to T.DAYS3, 7 to T.WEEK, 30 to T.MONTH).forEach { (d, label) ->
                Small(label, on = days == d, width = 90) { days = d }
            }
        }
        Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Column(Modifier.weight(1.4f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (rows.isEmpty()) Text(T.NO_SALES, fontSize = 24.sp, color = Color.Black)
                PagedGrid(rows, 6, 1, Modifier.weight(1f).fillMaxWidth()) { r, m ->
                    Plain("${r.first}   ${show(r.second)} ${T.KG}   ${show(r.third)} ${T.DT}", m, size = 18.sp) {}
                }
            }
            Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                totals.forEach { (label, v) ->
                    Text("$label: ${show(v)}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.Black, maxLines = 1)
                }
            }
        }
    }
}
