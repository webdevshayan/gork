package dev.shayan.gork

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Hands the downloaded update APK to the system package installer.
/// The only install path is the official system dialog: the app can request
/// the per-app "Install unknown apps" setting, but never flips it itself.
///
/// Movement 65 — also the Google deep-link receiver: the OAuth redirect
/// `dev.shayan.gork:/oauth2redirect?code=…` arrives here as an intent
/// (singleTop → onNewIntent when warm, onCreate when the process was
/// killed in the browser). The link is buffered with a monotonically
/// increasing id; Dart pulls it through the gork/applink channel.
class MainActivity : FlutterActivity() {
    companion object {
        @Volatile var applinkId: Int = 0
        @Volatile var applinkUri: String? = null
        @Volatile var applinkResult: MethodChannel.Result? = null
    }

    private var applinkChannel: MethodChannel? = null

    /// Buffers a gork deep link and answers a parked [take] at once.
    fun captureAppLink(uri: String?) {
        if (uri == null || !uri.startsWith("dev.shayan.gork:")) return
        applinkId += 1
        applinkUri = uri
        val parked = applinkResult
        applinkResult = null
        parked?.success(mapOf("id" to applinkId, "uri" to uri))
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Cold start: the deep link that STARTED this process (the app died
        // in the browser mid-sign-in) is the launch intent's data.
        captureAppLink(intent?.data?.toString())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureAppLink(intent.data?.toString())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        applinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "gork/applink"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        val lastSeen = call.argument<Int>("lastSeenId") ?: 0
                        if (applinkUri != null && applinkId > lastSeen) {
                            result.success(
                                mapOf("id" to applinkId, "uri" to applinkUri)
                            )
                        } else {
                            // Nothing new yet — park the result; the next
                            // onNewIntent/captureAppLink answers it.
                            applinkResult = result
                        }
                    }
                    "cancel" -> {
                        applinkResult = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gork/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> {
                        @Suppress("MissingPermission")
                        result.success(packageManager.canRequestPackageInstalls())
                    }
                    "openPermissionSettings" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NO_SETTINGS", e.message, null)
                        }
                    }
                    "openUrl" -> {
                        // Movement 62 — the Google consent page opens in the
                        // system browser; Google redirects back to the
                        // phone's loopback listener (http://127.0.0.1:port).
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.error("BAD_URL", "no url given", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NO_BROWSER", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("BAD_PATH", "no APK path given", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val apk = File(path)
                            if (!apk.exists() || apk.length() == 0L) {
                                result.error(
                                    "NO_APK",
                                    "APK missing or empty at $path",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", apk
                            )
                            val intent =
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(
                                        uri,
                                        "application/vnd.android.package-archive"
                                    )
                                    .addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_ACTIVITY_NEW_TASK
                                    )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
