package com.modellive.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ComponentCallbacks2
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// MainActivity + crash diagnostics.
//
// Everything the live stream does is written to a small file (live_steps.log)
// the moment it happens. If the app dies, the file survives, and on the next
// launch the Dart side prints it (and shows it on screen) together with:
//   * the Java/Kotlin exception that killed the app (native_crash.txt), and
//   * Android's own record of why the process died (ApplicationExitInfo,
//     Android 11+), which also covers native C++ crashes (SIGSEGV, SIGABRT).
// Everything is also sent to logcat with the tag "ModelLive".
class MainActivity : FlutterActivity() {

    companion object {
        const val TAG = "ModelLive"
        const val CHANNEL = "com.modellive.app/diagnostics"
        private const val MAX_STEP_FILE_BYTES = 200_000L
        private var handlerInstalled = false
        private val lock = Any()

        fun stepFile(ctx: Context) = File(ctx.filesDir, "live_steps.log")
        fun crashFile(ctx: Context) = File(ctx.filesDir, "native_crash.txt")

        private fun now(): String =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())

        fun appendStep(ctx: Context, line: String) {
            synchronized(lock) {
                try {
                    val f = stepFile(ctx)
                    if (f.exists() && f.length() > MAX_STEP_FILE_BYTES) f.delete()
                    FileOutputStream(f, true).use { out ->
                        out.write((line + "\n").toByteArray())
                        out.flush()
                    }
                } catch (_: Throwable) {
                }
            }
        }

        fun installCrashHandler(appContext: Context) {
            if (handlerInstalled) return
            handlerInstalled = true
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                try {
                    val sw = StringWriter()
                    throwable.printStackTrace(PrintWriter(sw))
                    val text = "TIME: ${now()}\nTHREAD: ${thread.name}\n$sw"
                    Log.e(TAG, "=== FATAL JAVA/KOTLIN EXCEPTION ===\n$text")
                    synchronized(lock) { crashFile(appContext).writeText(text) }
                    appendStep(
                        appContext,
                        "[${now()}] [NATIVE] FATAL exception on thread '${thread.name}': $throwable"
                    )
                } catch (_: Throwable) {
                }
                previous?.uncaughtException(thread, throwable)
            }
        }

        // Pulls readable text out of a binary crash dump (like the unix
        // "strings" command): library names, abort messages, signal info.
        private fun printableStrings(bytes: ByteArray, minLen: Int = 6, maxChars: Int = 60000): String {
            val out = StringBuilder()
            val cur = StringBuilder()
            for (b in bytes) {
                val c = b.toInt() and 0xff
                if (c in 32..126) {
                    cur.append(c.toChar())
                } else {
                    if (cur.length >= minLen) out.append(cur).append('\n')
                    cur.setLength(0)
                }
                if (out.length >= maxChars) break
            }
            if (cur.length >= minLen && out.length < maxChars) out.append(cur)
            return out.toString().take(maxChars)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashHandler(applicationContext)
        appendStep(applicationContext, "[${now()}] [NATIVE] Activity onCreate")
        super.onCreate(savedInstanceState)
    }

    override fun onStart() {
        super.onStart()
        appendStep(applicationContext, "[${now()}] [NATIVE] Activity onStart")
    }

    override fun onResume() {
        super.onResume()
        appendStep(applicationContext, "[${now()}] [NATIVE] Activity onResume")
    }

    override fun onPause() {
        appendStep(applicationContext, "[${now()}] [NATIVE] Activity onPause")
        super.onPause()
    }

    override fun onStop() {
        appendStep(applicationContext, "[${now()}] [NATIVE] Activity onStop")
        super.onStop()
    }

    override fun onDestroy() {
        appendStep(
            applicationContext,
            "[${now()}] [NATIVE] Activity onDestroy (isFinishing=$isFinishing)"
        )
        super.onDestroy()
    }

    override fun onLowMemory() {
        appendStep(applicationContext, "[${now()}] [NATIVE] onLowMemory")
        super.onLowMemory()
    }

    override fun onTrimMemory(level: Int) {
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
            appendStep(applicationContext, "[${now()}] [NATIVE] onTrimMemory level=$level")
        }
        super.onTrimMemory(level)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ctx = applicationContext

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "log" -> {
                            val line = call.arguments as? String ?: ""
                            Log.i(TAG, line)
                            appendStep(ctx, line)
                            result.success(null)
                        }
                        "resetSteps" -> {
                            synchronized(lock) { stepFile(ctx).delete() }
                            result.success(null)
                        }
                        "readSteps" -> {
                            val f = stepFile(ctx)
                            result.success(if (f.exists()) f.readText() else "")
                        }
                        "consumeCrash" -> {
                            val f = crashFile(ctx)
                            val text = if (f.exists()) f.readText() else ""
                            f.delete()
                            result.success(text)
                        }
                        "deviceInfo" -> {
                            result.success(
                                mapOf(
                                    "sdkInt" to Build.VERSION.SDK_INT,
                                    "release" to Build.VERSION.RELEASE,
                                    "manufacturer" to Build.MANUFACTURER,
                                    "model" to Build.MODEL,
                                    "targetSdk" to ctx.applicationInfo.targetSdkVersion,
                                    "abis" to Build.SUPPORTED_ABIS.joinToString(","),
                                    "package" to ctx.packageName
                                )
                            )
                        }
                        "consumeExitInfo" -> result.success(consumeExitInfo(ctx))
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("DIAG", t.toString(), null)
                }
            }
    }

    // Android 11+ keeps a short history of why this app's process ended.
    // Only entries newer than the last time we reported are returned.
    private fun consumeExitInfo(ctx: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val prefs = ctx.getSharedPreferences("modellive_diag", Context.MODE_PRIVATE)
        val lastSeen = prefs.getLong("last_exit_ts", 0L)
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val infos = am.getHistoricalProcessExitReasons(ctx.packageName, 0, 5)
        val out = mutableListOf<Map<String, Any?>>()
        var newest = lastSeen
        for (info in infos) {
            if (info.timestamp <= lastSeen) continue
            if (info.timestamp > newest) newest = info.timestamp
            var trace = ""
            if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
                info.reason == ApplicationExitInfo.REASON_ANR
            ) {
                try {
                    info.traceInputStream?.use { stream ->
                        val buf = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        while (buf.size() < 400_000) {
                            val n = stream.read(chunk)
                            if (n <= 0) break
                            buf.write(chunk, 0, n)
                        }
                        trace = printableStrings(buf.toByteArray())
                    }
                } catch (_: Throwable) {
                }
            }
            out.add(
                mapOf(
                    "reason" to reasonName(info.reason),
                    "description" to (info.description ?: ""),
                    "status" to info.status,
                    "timestamp" to SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
                        .format(Date(info.timestamp)),
                    "importance" to info.importance,
                    "trace" to trace
                )
            )
        }
        prefs.edit().putLong("last_exit_ts", newest).apply()
        return out
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR (app not responding)"
        ApplicationExitInfo.REASON_CRASH -> "CRASH (Java/Kotlin exception)"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE (C/C++ crash in a native library)"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF (app called exit)"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED (killed by a signal)"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY (killed by Android, out of memory)"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE (a permission was changed while running)"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
        else -> "REASON_$reason"
    }
}
