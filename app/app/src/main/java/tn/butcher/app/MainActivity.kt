package tn.butcher.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
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
    const val FREE = "بلاش"
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
    private val dao = AppDb.get(ctx).dao()
    val productEvents = dao.productEvents()
    val lastLiveSale = dao.lastLiveSale()
    val liveSales = dao.liveSales()

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

    suspend fun addSale(p: ProductView, kind: String, total: Double, kgTyped: Double?, credit: Boolean) {
        val kg = kgTyped ?: (round(total / p.price * 1000) / 1000)
        dao.insert(Sale(newId(), p.uuid, total, p.price, kg, kind, credit, System.currentTimeMillis()))
        kick()
    }

    /** Edit is a void plus a new row, so the server keeps both. The sale keeps its time. */
    suspend fun editSale(s: Sale, total: Double, kg: Double) {
        dao.insert(Void(newId(), "sales", s.uuid, System.currentTimeMillis()))
        dao.insert(Sale(newId(), s.productUuid, total, s.pricePerKg, kg, s.kind, s.credit, s.deviceTime))
        kick()
    }

    suspend fun undoSale(s: Sale) {
        dao.insert(Void(newId(), "sales", s.uuid, System.currentTimeMillis()))
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
fun Small(text: String, enabled: Boolean = true, width: Int = 110, onClick: () -> Unit) {
    Plain(text, Modifier.width(width.dp).fillMaxHeight(), enabled = enabled, size = 18.sp, onClick = onClick)
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
            Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Plain(T.GOODS, Modifier.weight(1f).fillMaxWidth(), size = 40.sp) { go("products") }
                Plain(T.HISTORY, Modifier.weight(1f).fillMaxWidth(), size = 40.sp) { go("history") }
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

/** Fixed grid, never scrolls. Green has a price, grey has none. Extra products go to the next page. */
@Composable
fun ProductGrid(products: List<ProductView>, modifier: Modifier, pickable: (ProductView) -> Boolean = { true }, onTap: (ProductView) -> Unit) {
    val rows = 4
    val cols = 5
    val slots = rows * cols
    val needMore = products.size > slots
    val pageSize = if (needMore) slots - 1 else slots
    val pages = ceil(products.size.toDouble() / pageSize).toInt().coerceAtLeast(1)
    var page by rememberSaveable { mutableStateOf(0) }
    val shown = products.drop(page.coerceAtMost(pages - 1) * pageSize).take(pageSize)
    val cells = buildList<@Composable (Modifier) -> Unit> {
        shown.forEach { p ->
            add { m -> Plain(p.name, m, enabled = pickable(p), dim = p.price <= 0, fill = Color(0xFFA5D6A7), size = 20.sp) { onTap(p) } }
        }
        if (needMore) add { m -> Plain(T.MORE, m, size = 20.sp) { page = (page + 1) % pages } }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (r in 0 until rows) {
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (c in 0 until cols) {
                    val cell = cells.getOrNull(r * cols + c)
                    if (cell != null) cell(Modifier.weight(1f).fillMaxSize())
                    else Spacer(Modifier.weight(1f))
                }
            }
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
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var discount by rememberSaveable { mutableStateOf(false) }
    var free by rememberSaveable { mutableStateOf(false) }
    var credit by rememberSaveable { mutableStateOf(false) }
    var total by rememberSaveable { mutableStateOf("") }
    var kgText by rememberSaveable { mutableStateOf("") }
    var onKg by rememberSaveable { mutableStateOf(false) }

    val kind = if (free) "free" else if (discount) "discount" else "paid"
    val showTotal = !free
    val showKg = free || discount
    val typingKg = free || (discount && onKg)
    val product = products.firstOrNull { it.uuid == selected }
    val totalNum = if (free) 0.0 else num(total)
    val kgNum = num(kgText)
    val valid = product != null && product.price > 0 && totalNum != null && totalNum >= 0 &&
        (kind == "paid" && totalNum > 0 || kind != "paid" && kgNum != null && kgNum > 0)

    val reset = { total = ""; kgText = ""; credit = false; discount = false; free = false; onKg = false; selected = null }
    BackHandler(enabled = product != null) { reset() }

    if (product == null) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Bar {
                Small(T.BACK, onClick = back)
                Title(T.PICK, Modifier.weight(1f))
                val s = lastSale
                val lastName = products.firstOrNull { it.uuid == s?.productUuid }?.name ?: ""
                Small(if (s != null) "${T.UNDO} $lastName ${s.total}" else T.UNDO, enabled = s != null, width = 240) {
                    s?.let { scope.launch { withContext(Dispatchers.IO) { repo.undoSale(it) } } }
                }
            }
            ProductGrid(products, Modifier.weight(1f).fillMaxWidth(), pickable = { it.price > 0 }) { selected = it.uuid }
        }
        return
    }

    Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Column(Modifier.weight(1.4f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (showTotal) Readout(T.TOTAL, total, !typingKg, Modifier.weight(0.6f).fillMaxWidth()) { onKg = false }
            if (showKg) Readout(T.KILO, kgText, typingKg, Modifier.weight(0.6f).fillMaxWidth()) { onKg = true }
            if (typingKg) NumPad(Modifier.weight(3f).fillMaxWidth(), kgText) { kgText = it }
            else NumPad(Modifier.weight(3f).fillMaxWidth(), total) { total = it }
        }
        Column(Modifier.weight(1f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Title(product.name, Modifier.fillMaxWidth())
            Plain(T.BACK, Modifier.weight(1f).fillMaxWidth(), size = 20.sp, onClick = reset)
            Plain(T.DISCOUNT, Modifier.weight(1f).fillMaxWidth(), on = discount, size = 20.sp) { discount = !discount; free = false; onKg = false }
            Plain(T.FREE, Modifier.weight(1f).fillMaxWidth(), on = free, size = 20.sp) { free = !free; discount = false }
            Plain(T.CREDIT, Modifier.weight(1f).fillMaxWidth(), on = credit, size = 20.sp) { credit = !credit }
            Plain(T.SAVE, Modifier.weight(1.5f).fillMaxWidth(), enabled = valid, size = 24.sp) {
                val p = product
                val t = totalNum ?: return@Plain
                val k = kind
                val kg = if (k == "paid") null else kgNum
                val c = credit
                scope.launch { withContext(Dispatchers.IO) { repo.addSale(p, k, t, kg, c) } }
                reset()
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
