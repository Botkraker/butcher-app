package tn.butcher.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The few things Dart cannot do alone:
 * - the phone's voice typing (same intent as the Kotlin app),
 * - the SharedPreferences files the Kotlin app wrote ("butcher", "seed"), so no setting is lost,
 * - the first install time (for the "3 days without sending" warning).
 */
class MainActivity : FlutterActivity() {
    private var speechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "butcher/native").setMethodCallHandler { call, result ->
            val file = call.argument<String>("file") ?: "butcher"
            val key = call.argument<String>("key") ?: ""
            val p = getSharedPreferences(file, Context.MODE_PRIVATE)
            when (call.method) {
                "speech" -> speech(result)
                "firstInstallTime" -> result.success(packageManager.getPackageInfo(packageName, 0).firstInstallTime)
                "getString" -> result.success(if (p.contains(key)) p.getString(key, null) else null)
                "getLong" -> result.success(if (p.contains(key)) p.getLong(key, 0L) else null)
                "getBool" -> result.success(if (p.contains(key)) p.getBoolean(key, false) else null)
                "putString" -> { p.edit().putString(key, call.argument<String>("value")).apply(); result.success(null) }
                "putLong" -> { p.edit().putLong(key, (call.argument<Number>("value") ?: 0).toLong()).apply(); result.success(null) }
                "putBool" -> { p.edit().putBoolean(key, call.argument<Boolean>("value") ?: false).apply(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    /** Opens the phone's own voice typing in Tunisian Arabic. No voice app: shows a message, returns null. */
    private fun speech(result: MethodChannel.Result) {
        speechResult?.success(null)
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ar-TN")
        try {
            speechResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(i, SPEECH)
        } catch (e: ActivityNotFoundException) {
            speechResult = null
            Toast.makeText(this, "الصوت موش موجود في التلفون", Toast.LENGTH_LONG).show()
            result.success(null)
        }
    }

    @Deprecated("Uses the old result API, enough for one intent.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SPEECH) return
        val text = if (resultCode == Activity.RESULT_OK) data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null
        speechResult?.success(text)
        speechResult = null
    }

    companion object {
        private const val SPEECH = 7
    }
}
