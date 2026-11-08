package tn.butcher.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.room.withTransaction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.round

/** All words shown to the butcher, in Tunisian. Change wording here only. */
object T {
    const val SELL = "بيعة"
    const val GOODS = "السلعة"
    const val BACK = "ارجع"
    const val SAVE = "سجّل"
    const val UNDO = "فسّخ"
    const val DISCOUNT = "ريميز"
    const val CREDIT = "كريدي"
    const val TOTAL = "الحساب"
    const val KILO = "الكيلو"
    const val PRICE = "سوم الكيلو"
    const val NAME = "اسم السلعة"
    const val NEW = "+ سلعة جديدة"
    const val ADD = "زيد"
    const val REMOVE = "نحّيها"
    const val MORE = "سلعة أخرى"
    const val PICK = "اختار السلعة"
    const val NEXT = "كمّل"
    const val HISTORY = "البيعات"
    const val OLDER = "اللي قبل"
    const val NO_SALES = "ما فما حتى بيعة"
    const val TEST = "جرّب الانترنت"
    const val SEND_ALL = "ابعث الكل توا"
    const val SEND_TEST = "ابعث تجربة"
    const val LAST_SYNC = "آخر بعثة"
    const val WARN = "ما تبعثش الحساب من 3 أيام. شعّل الانترنت."
    const val MIC = "🎤 احكي"
    const val NO_MIC = "الصوت موش موجود في التلفون"
    const val CREDITS = "الكريدي"
    const val WHO = "شكون خذا بالكريدي؟"
    const val NEW_PERSON = "+ اسم جديد"
    const val NO_CREDIT = "ما فما حتى كريدي"
    const val OWES = "عليه"
    const val AMOUNT = "المبلغ"
    const val ADD_DEBT = "زيد كريدي"
    const val PAID_BACK = "خلّص"
    const val SPEND = "مصروف الدار"
    const val DETAILS = "التفاصيل (موش لازم)"
    const val TODAY = "اليوم"
    const val BUY = "الشراء"
    const val WHAT_BOUGHT = "شنوّة شريت؟"
    const val PAY_ONLY = "خلّص برك"
    const val GAVE = "عطيت"
    const val OWE_AFTER = "يبقى عليك"
    const val DASH = "الملخّص"
    const val DAYS3 = "3 أيام"
    const val WEEK = "جمعة"
    const val MONTH = "شهر"
    const val SOLD = "البيع"
    const val BOUGHT = "الشراء"
    const val CASH = "فلوس الكاسة"
    const val CREDIT_GIVEN = "كريدي جديد"
    const val CREDIT_BACK = "رجّعوا"
    const val KG = "كغ"
    const val DT = "د"
}

/** Pre-built list, added once on first run. Prices start empty; he sets them. */
val STARTER_PRODUCTS = listOf(
    "علوش", "هبرة عجول", "كتلات علوش", "أنتروكوت بقري", "فيلي", "فو فيلي", "كبدة علوش", "كبدة بقري",
    "كمونية علوش", "كمونية بقري", "مرقز", "صدرة", "هرقمة", "لحم راس", "كرشة",
)

data class ProductView(val uuid: String, val name: String, val price: Double, val hidden: Boolean)

fun foldProducts(events: List<ProductEvent>): List<ProductView> {
    val m = LinkedHashMap<String, ProductView>()
    for (e in events) {
        val cur = m[e.productUuid]
        when (e.kind) {
            "create" -> m[e.productUuid] = ProductView(e.productUuid, e.name, e.pricePerKg ?: 0.0, false)
            "price" -> if (cur != null && e.pricePerKg != null) m[e.productUuid] = cur.copy(price = e.pricePerKg)
            "hide" -> if (cur != null) m[e.productUuid] = cur.copy(hidden = true)
        }
    }
    return m.values.toList()
}

fun num(s: String): Double? = s.trim().replace(',', '.').toDoubleOrNull()
fun newId(): String = UUID.randomUUID().toString()

/** Every save writes to Room first, then asks the worker to sync. */
class Repo(private val ctx: Context) {
    private val db = AppDb.get(ctx)
    private val dao = db.dao()
    val productEvents = dao.productEvents()
    val lastLiveSale = dao.lastLiveSale()
    val liveSales = dao.liveSales()
    val creditEvents = dao.creditEvents()
    val voidedIds = dao.voidedIds()
    val livePurchases = dao.livePurchases()
    val liveCashMoves = dao.liveCashMoves()
    fun salesSince(since: Long) = dao.salesSince(since)

    private fun kick() = SyncWorker.enqueue(ctx)

    suspend fun seedProducts() {
        val prefs = ctx.getSharedPreferences("seed", Context.MODE_PRIVATE)
        if (prefs.getBoolean("done", false)) return
        STARTER_PRODUCTS.forEach { dao.insert(ProductEvent(newId(), newId(), it, "create", 0.0, System.currentTimeMillis())) }
        prefs.edit().putBoolean("done", true).apply()
        kick()
    }

    suspend fun addProduct(name: String, price: Double) {
        dao.insert(ProductEvent(newId(), newId(), name, "create", price, System.currentTimeMillis()))
        kick()
    }

    suspend fun setPrice(p: ProductView, price: Double) {
        dao.insert(ProductEvent(newId(), p.uuid, p.name, "price", price, System.currentTimeMillis()))
        kick()
    }

    suspend fun hide(p: ProductView) {
        dao.insert(ProductEvent(newId(), p.uuid, p.name, "hide", null, System.currentTimeMillis()))
        kick()
    }

    /** person is set for a credit sale: the sale and its debt are saved together. */
    suspend fun addSale(p: ProductView, kind: String, total: Double, kgTyped: Double?, person: String?) {
        val kg = kgTyped ?: r3(total / p.price)
        val sale = Sale(newId(), p.uuid, total, p.price, kg, kind, person != null, System.currentTimeMillis())
        db.withTransaction {
            dao.insert(sale)
            if (person != null) dao.insert(CreditEvent(newId(), person, total, "debt", sale.uuid, sale.deviceTime))
        }
        kick()
    }

    /** Edit is a void plus a new row, so the server keeps both. The sale keeps its time. A credit sale keeps its debt. */
    suspend fun editSale(s: Sale, total: Double, kg: Double) {
        db.withTransaction {
            val debt = if (s.credit) dao.creditForSale(s.uuid) else null
            dao.insert(Void(newId(), "sales", s.uuid, System.currentTimeMillis()))
            val n = Sale(newId(), s.productUuid, total, s.pricePerKg, kg, s.kind, debt != null, s.deviceTime)
            dao.insert(n)
            if (debt != null) dao.insert(CreditEvent(newId(), debt.person, total, "debt", n.uuid, debt.deviceTime))
        }
        kick()
    }

    suspend fun undoSale(s: Sale) = void("sales", s.uuid)

    suspend fun void(table: String, uuid: String) {
        dao.insert(Void(newId(), table, uuid, System.currentTimeMillis()))
        kick()
    }

    suspend fun addCredit(person: String, amount: Double, kind: String) {
        dao.insert(CreditEvent(newId(), person, amount, kind, null, System.currentTimeMillis()))
        kick()
    }

    /** Money taken from the till for the house. Saved as a negative cash move. */
    suspend fun addSpending(amount: Double, details: String) {
        dao.insert(CashMove(newId(), -amount, details, System.currentTimeMillis()))
        kick()
    }

    suspend fun addPurchase(item: String, kg: Double, pricePerKg: Double, paid: Double) {
        dao.insert(Purchase(newId(), item, kg, pricePerKg, r3(kg * pricePerKg), paid, System.currentTimeMillis()))
        kick()
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        SyncWorker.enqueue(this)
        val repo = Repo(this)
        setContent {
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                MaterialTheme {
                    Surface(Modifier.fillMaxSize(), color = Color.White) { App(repo) }
                }
            }
        }
    }
}

/** Plain box button: fills whatever space its modifier gives it. */
@Composable
fun Plain(
    text: String,
    modifier: Modifier,
    on: Boolean = false,
    enabled: Boolean = true,
    dim: Boolean = false,
    fill: Color = Color(0xFFDDDDDD),
    size: TextUnit = 28.sp,
    onClick: () -> Unit,
) {
    val bg = when { !enabled || dim -> Color(0xFFEEEEEE); on -> Color.Black; else -> fill }
    val fg = when { !enabled || dim -> Color.Gray; on -> Color.White; else -> Color.Black }
    Box(
        modifier.background(bg).border(1.dp, Color.Black)
            .clickable(enabled = enabled, onClick = onClick).padding(2.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = fg, fontSize = size, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 3)
    }
}

/** Thin strip at the top of a screen, for small buttons and the title. */
@Composable
fun Bar(content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(48.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun Small(text: String, enabled: Boolean = true, on: Boolean = false, width: Int = 110, onClick: () -> Unit) {
    Plain(text, Modifier.width(width.dp).fillMaxHeight(), on = on, enabled = enabled, size = 18.sp, onClick = onClick)
}

@Composable
fun Title(text: String, modifier: Modifier) {
    Text(text, modifier, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.Black, maxLines = 1)
}

@Composable
fun App(repo: Repo) {
    var screen by rememberSaveable { mutableStateOf("home") }
    LaunchedEffect(Unit) { withContext(Dispatchers.IO) { repo.seedProducts() } }
    BackHandler(enabled = screen != "home") { screen = "home" }
    val back = { screen = "home" }
    Box(Modifier.fillMaxSize().padding(4.dp)) {
        when (screen) {
            "sale" -> SaleScreen(repo, back)
            "products" -> ProductsScreen(repo, back)
            "history" -> HistoryScreen(repo, back)
            "credits" -> CreditScreen(repo, back)
            "buy" -> PurchaseScreen(repo, back)
            "spend" -> SpendingScreen(repo, back)
            "dash" -> DashboardScreen(repo, back)
            "debug" -> DebugScreen(back)
            else -> HomeScreen { screen = it }
        }
    }
}

@Composable
fun HomeScreen(go: (String) -> Unit) {
    val ctx = LocalContext.current
    val last = Prefs.lastSync(ctx)
    val base = if (last > 0) last else ctx.packageManager.getPackageInfo(ctx.packageName, 0).firstInstallTime
    val stale = System.currentTimeMillis() - base > 3L * 24 * 3600 * 1000
    val t = if (last > 0) SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(last)) else "—"
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Plain(T.SELL, Modifier.weight(2f).fillMaxSize(), size = 72.sp) { go("sale") }
            Column(Modifier.weight(1.4f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val buttons = listOf(
                    listOf(T.GOODS to "products", T.HISTORY to "history"),
                    listOf(T.CREDITS to "credits", T.BUY to "buy"),
                    listOf(T.SPEND to "spend", T.DASH to "dash"),
                )
                buttons.forEach { row ->
                    Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        row.forEach { (label, target) -> Plain(label, Modifier.weight(1f).fillMaxSize(), size = 26.sp) { go(target) } }
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (stale) T.WARN else "${T.LAST_SYNC}: $t",
                color = if (stale) Color.Red else Color.Black,
                fontSize = 20.sp,
                modifier = Modifier.weight(1f),
            )
            Text(T.TEST, fontSize = 18.sp, modifier = Modifier.clickable { go("debug") }.padding(8.dp))
        }
    }
}

/** Fixed grid, never scrolls. Extra items go to the next page. */
@Composable
fun <E> PagedGrid(items: List<E>, rows: Int, cols: Int, modifier: Modifier, cell: @Composable (E, Modifier) -> Unit) {
    val slots = rows * cols
    val needMore = items.size > slots
    val pageSize = if (needMore) slots - 1 else slots
    val pages = ceil(items.size.toDouble() / pageSize).toInt().coerceAtLeast(1)
    var page by rememberSaveable { mutableStateOf(0) }
    val shown = items.drop(page.coerceAtMost(pages - 1) * pageSize).take(pageSize)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (r in 0 until rows) {
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (c in 0 until cols) {
                    val i = r * cols + c
                    when {
                        i < shown.size -> cell(shown[i], Modifier.weight(1f).fillMaxSize())
                        needMore && i == slots - 1 -> Plain(T.MORE, Modifier.weight(1f).fillMaxSize(), size = 20.sp) { page = (page + 1) % pages }
                        else -> Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** Green has a price, grey has none. */
@Composable
fun ProductGrid(products: List<ProductView>, modifier: Modifier, pickable: (ProductView) -> Boolean = { true }, onTap: (ProductView) -> Unit) {
    PagedGrid(products, 4, 5, modifier) { p, m ->
        Plain(p.name, m, enabled = pickable(p), dim = p.price <= 0, fill = Color(0xFFA5D6A7), size = 20.sp) { onTap(p) }
    }
}

/** Opens the phone's own voice typing in Tunisian Arabic. No internet or no voice app: shows a message. */
@Composable
fun MicButton(onText: (String) -> Unit) {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let(onText)
        }
    }
    Small(T.MIC, width = 100) {
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-TN")
        try {
            launcher.launch(i)
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(ctx, T.NO_MIC, Toast.LENGTH_LONG).show()
        }
    }
}

/** One text box, voice, and old names as buttons. Tapping an old name is enough; no typing. */
@Composable
fun NamePicker(
    title: String,
    value: String,
    onChange: (String) -> Unit,
    suggestions: List<String>,
    back: () -> Unit,
    action: String,
    actionEnabled: Boolean,
    onAction: () -> Unit,
    onPick: (String) -> Unit = onChange,
    appendVoice: Boolean = false,
    extra: @Composable RowScope.() -> Unit = {},
) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Bar {
            Small(T.BACK, onClick = back)
            Title(title, Modifier.weight(1f))
            extra()
            MicButton { said -> onChange(if (appendVoice) cleanName("$value $said") else cleanName(said)) }
            Small(action, enabled = actionEnabled, onClick = onAction)
        }
        OutlinedTextField(value, onChange, singleLine = true, textStyle = TextStyle(fontSize = 24.sp), modifier = Modifier.fillMaxWidth())
        val q = cleanName(value)
        val shown = suggestions.filter { q.isEmpty() || it.contains(q, ignoreCase = true) }
        PagedGrid(shown, 2, 4, Modifier.weight(1f).fillMaxWidth()) { s, m ->
            Plain(s, m, on = s == q, size = 20.sp) { onPick(s) }
        }
    }
}

/** On-screen digits, so the phone keyboard never covers the screen. */
@Composable
fun NumPad(modifier: Modifier, value: String, onChange: (String) -> Unit) {
    val rows = listOf("123", "456", "789", ".0<")
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            rows.forEach { keys ->
                Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    keys.forEach { k ->
                        Plain(if (k == '<') "⌫" else k.toString(), Modifier.weight(1f).fillMaxSize(), size = 32.sp) {
                            when {
                                k == '<' -> onChange(value.dropLast(1))
                                k == '.' && '.' in value -> {}
                                else -> onChange(value + k)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun Readout(label: String, value: String, active: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.border(if (active) 3.dp else 1.dp, Color.Black).clickable(onClick = onClick).padding(horizontal = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("$label: $value", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.Black, maxLines = 1)
    }
}

@Composable
fun SaleScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val products = foldProducts(repo.productEvents.collectAsState(emptyList()).value).filter { !it.hidden }
    val lastSale by repo.lastLiveSale.collectAsState(null)
    val people = peopleByRecent(repo.creditEvents.collectAsState(emptyList()).value)
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var discount by rememberSaveable { mutableStateOf(false) }
    var credit by rememberSaveable { mutableStateOf(false) }
    var askName by rememberSaveable { mutableStateOf(false) }
    var person by rememberSaveable { mutableStateOf("") }
    var total by rememberSaveable { mutableStateOf("") }
    var kgText by rememberSaveable { mutableStateOf("") }
    var onKg by rememberSaveable { mutableStateOf(false) }

    val kind = if (discount) "discount" else "paid"
    val typingKg = discount && onKg
    val product = products.firstOrNull { it.uuid == selected }
    val totalNum = num(total)
    val kgNum = num(kgText)
    // Paid: total > 0. Discount: total >= 0 and the kg he really gave. Credit: total > 0.
    val valid = product != null && product.price > 0 && totalNum != null &&
        (if (discount) totalNum >= 0 && kgNum != null && kgNum > 0 else totalNum > 0) &&
        (!credit || totalNum > 0)

    val reset = { total = ""; kgText = ""; credit = false; discount = false; onKg = false; askName = false; person = ""; selected = null }
    val save: () -> Unit = {
        val p = product
        val t = totalNum
        val who = if (credit) canonical(person, people) else null
        if (p != null && t != null && valid && who != "") {
            val k = kind
            val kg = if (discount) kgNum else null
            scope.launch { withContext(Dispatchers.IO) { repo.addSale(p, k, t, kg, who) } }
            reset()
        }
    }
    BackHandler(enabled = product != null) { if (askName) askName = false else reset() }

    if (product == null) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = back)
                Title(T.PICK, Modifier.weight(1f))
                val s = lastSale
                val lastName = products.firstOrNull { it.uuid == s?.productUuid }?.name ?: ""
                Small(if (s != null) "${T.UNDO} $lastName ${show(s.total)}" else T.UNDO, enabled = s != null, width = 240) {
                    s?.let { scope.launch { withContext(Dispatchers.IO) { repo.undoSale(it) } } }
                }
            }
            ProductGrid(products, Modifier.weight(1f).fillMaxWidth(), pickable = { it.price > 0 }) { selected = it.uuid }
        }
        return
    }

    if (askName) {
        NamePicker(
            T.WHO, person, { person = it }, people,
            back = { askName = false }, action = T.SAVE, actionEnabled = cleanName(person).isNotEmpty(), onAction = save,
        )
        return
    }

    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Column(Modifier.weight(1.4f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Readout(T.TOTAL, total, !typingKg, Modifier.weight(0.6f).fillMaxWidth()) { onKg = false }
            if (discount) Readout(T.KILO, kgText, typingKg, Modifier.weight(0.6f).fillMaxWidth()) { onKg = true }
            if (typingKg) NumPad(Modifier.weight(3f).fillMaxWidth(), kgText) { kgText = it }
            else NumPad(Modifier.weight(3f).fillMaxWidth(), total) { total = it }
        }
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title(product.name, Modifier.fillMaxWidth())
            Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = reset)
            Plain(T.DISCOUNT, Modifier.weight(1f).fillMaxWidth(), on = discount, size = 20.sp) { discount = !discount; onKg = false }
            Plain(T.CREDIT, Modifier.weight(1f).fillMaxWidth(), on = credit, size = 20.sp) { credit = !credit }
            Plain(if (credit) T.NEXT else T.SAVE, Modifier.weight(1.5f).fillMaxWidth(), enabled = valid, size = 24.sp) {
                if (credit) askName = true else save()
            }
        }
    }
}

/** Three separate screens: the list, the new name, and the price. */
@Composable
fun ProductsScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val products = foldProducts(repo.productEvents.collectAsState(emptyList()).value).filter { !it.hidden }
    var mode by rememberSaveable { mutableStateOf("list") }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var name by rememberSaveable { mutableStateOf("") }
    var price by rememberSaveable { mutableStateOf("") }
    val product = products.firstOrNull { it.uuid == selected }
    val pr = num(price)
    val clear = { mode = "list"; selected = null; name = ""; price = "" }
    BackHandler(enabled = mode != "list") { clear() }

    when (mode) {
        "list" -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = back)
                Title(T.GOODS, Modifier.weight(1f))
                Small(T.NEW, width = 180) { clear(); mode = "name" }
            }
            ProductGrid(products, Modifier.weight(1f).fillMaxWidth()) {
                selected = it.uuid
                price = if (it.price > 0) it.price.toString() else ""
                mode = "price"
            }
        }
        "name" -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = clear)
                Title(T.NEW, Modifier.weight(1f))
                Small(T.NEXT, enabled = name.isNotBlank()) { mode = "price" }
            }
            OutlinedTextField(name, { name = it }, label = { Text(T.NAME) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        else -> Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            NumPad(Modifier.weight(1.4f).fillMaxSize(), price) { price = it }
            Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Title(product?.name ?: name, Modifier.fillMaxWidth())
                Readout(T.PRICE, price, true, Modifier.weight(1f).fillMaxWidth()) {}
                Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = clear)
                if (product != null) Plain(T.REMOVE, Modifier.weight(1f).fillMaxWidth(), size = 20.sp) {
                    scope.launch { withContext(Dispatchers.IO) { repo.hide(product) } }
                    clear()
                }
                Plain(if (product == null) T.ADD else T.SAVE, Modifier.weight(1.5f).fillMaxWidth(), enabled = pr != null && pr > 0, size = 24.sp) {
                    val v = pr ?: return@Plain
                    val p = product
                    val n = name.trim()
                    scope.launch { withContext(Dispatchers.IO) { if (p != null) repo.setPrice(p, v) else repo.addProduct(n, v) } }
                    clear()
                }
            }
        }
    }
}

/** Two separate screens: the list of sales, and the edit of one sale. */
@Composable
fun HistoryScreen(repo: Repo, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    val sales by repo.liveSales.collectAsState(emptyList())
    val names = foldProducts(repo.productEvents.collectAsState(emptyList()).value).associate { it.uuid to it.name }
    val fmt = remember { SimpleDateFormat("dd/MM HH:mm", Locale.US) }
    var page by remember { mutableStateOf(0) }
    var selected by remember { mutableStateOf<String?>(null) }
    var value by remember { mutableStateOf("") }
    val perPage = 5
    val pages = ceil(sales.size.toDouble() / perPage).toInt().coerceAtLeast(1)
    val shown = sales.drop(page.coerceAtMost(pages - 1) * perPage).take(perPage)
    val sale = sales.firstOrNull { it.uuid == selected }
    val free = sale?.kind == "free"
    val v = num(value)
    val clear = { selected = null; value = "" }
    BackHandler(enabled = sale != null) { clear() }

    if (sale == null) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = back)
                Title(T.HISTORY, Modifier.weight(1f))
                Small(T.OLDER, enabled = pages > 1) { page = (page + 1) % pages }
            }
            if (sales.isEmpty()) Text(T.NO_SALES, fontSize = 28.sp, color = Color.Black)
            for (i in 0 until perPage) {
                val s = shown.getOrNull(i)
                if (s == null) Spacer(Modifier.weight(1f))
                else Plain(
                    "${names[s.productUuid] ?: ""}  ${s.total}  ${fmt.format(Date(s.deviceTime))}" + if (s.credit) "  ${T.CREDIT}" else "",
                    Modifier.weight(1f).fillMaxWidth(), size = 20.sp,
                ) { selected = s.uuid; value = (if (s.kind == "free") s.kg else s.total).toString() }
            }
        }
        return
    }

    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        NumPad(Modifier.weight(1.4f).fillMaxSize(), value) { value = it }
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title("${names[sale.productUuid] ?: ""}  ${fmt.format(Date(sale.deviceTime))}", Modifier.fillMaxWidth())
            Readout(if (free) T.KILO else T.TOTAL, value, true, Modifier.weight(1f).fillMaxWidth()) {}
            Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = clear)
            Plain(T.UNDO, Modifier.weight(1f).fillMaxWidth(), size = 20.sp) {
                val s = sale
                scope.launch { withContext(Dispatchers.IO) { repo.undoSale(s) } }
                clear()
            }
            Plain(T.SAVE, Modifier.weight(1.5f).fillMaxWidth(), enabled = v != null && v > 0, size = 24.sp) {
                val s = sale
                val n = v ?: return@Plain
                val total = if (free) 0.0 else n
                val kg = when (s.kind) {
                    "free" -> n
                    "paid" -> round(n / s.pricePerKg * 1000) / 1000
                    else -> s.kg
                }
                scope.launch { withContext(Dispatchers.IO) { repo.editSale(s, total, kg) } }
                clear()
            }
        }
    }
}

@Composable
fun DebugScreen(back: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var result by remember { mutableStateOf("") }
    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), onClick = back)
            Plain(T.SEND_ALL, Modifier.weight(1f).fillMaxWidth()) {
                result = "..."
                scope.launch { result = withContext(Dispatchers.IO) { pushAll(ctx) ?: "OK" } }
            }
            Plain(T.SEND_TEST, Modifier.weight(1f).fillMaxWidth()) {
                result = "..."
                scope.launch {
                    result = withContext(Dispatchers.IO) {
                        try {
                            if (BuildConfig.NEON_SQL_URL.isBlank()) "NEON_SQL_URL empty (local.properties)"
                            else {
                                val q = Neon.query(
                                    "debug_pings",
                                    listOf("uuid" to 'u', "note" to 's', "device_time" to 't'),
                                    listOf(newId(), "test", System.currentTimeMillis()),
                                    System.currentTimeMillis(),
                                )
                                val (code, body) = Neon.post(listOf(q))
                                "HTTP $code\n$body"
                            }
                        } catch (e: Exception) {
                            "ERROR: ${e.javaClass.simpleName}: ${e.message}"
                        }
                    }
                }
            }
        }
        Column(Modifier.weight(2f).fillMaxSize().verticalScroll(rememberScrollState())) {
            Text(result, fontSize = 18.sp, color = Color.Black)
        }
    }
}
