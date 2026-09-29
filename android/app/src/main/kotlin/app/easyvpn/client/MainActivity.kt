package app.easyvpn.client

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Hosts the Flutter UI and the `easyvpn/platform` channel used by
 * lib/core/util/platform_service.dart:
 *
 *   simCountry / networkCountry / timezone   -> String?
 *   prepareVpn                               -> Boolean (system VPN permission dialog)
 *   establishVpn {mtu, ipv6, include, exclude} -> Int (TUN file descriptor for the Go core)
 *   stopVpn                                  -> Boolean
 *   installedApps                            -> [{package, label}]
 *   setAutoStart {enabled}                   -> Boolean
 *
 * Native -> Dart calls: `vpnRevoked` (system or notification action ended the VPN)
 * and `toggle` (Quick Settings tile / notification tap).
 */
class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "easyvpn/platform"
        const val REQ_VPN = 4101
        const val ACTION_TOGGLE = "app.easyvpn.client.TOGGLE"

        @Volatile var channel: MethodChannel? = null

        /** Called by [EasyVpnService] when the system revokes or the user stops the VPN. */
        fun notifyRevoked() {
            channel?.invokeMethod("vpnRevoked", null)
        }
    }

    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "simCountry" -> result.success(telephony()?.simCountryIso?.takeIf { it.length == 2 }?.uppercase())
                "networkCountry" -> result.success(telephony()?.networkCountryIso?.takeIf { it.length == 2 }?.uppercase())
                "timezone" -> result.success(TimeZone.getDefault().id)
                "prepareVpn" -> prepareVpn(result)
                "establishVpn" -> {
                    val mtu = call.argument<Int>("mtu") ?: 9000
                    val ipv6 = call.argument<Boolean>("ipv6") ?: false
                    val include = call.argument<List<String>>("include") ?: emptyList()
                    val exclude = call.argument<List<String>>("exclude") ?: emptyList()
                    val fd = EasyVpnService.establishFromActivity(this, mtu, ipv6, include, exclude)
                    if (fd > 0) result.success(fd) else result.error("vpn", "VpnService.establish() failed", null)
                }
                "stopVpn" -> {
                    EasyVpnService.stopFromActivity(this)
                    result.success(true)
                }
                "installedApps" -> result.success(installedApps())
                "setAutoStart" -> {
                    getSharedPreferences("easyvpn", MODE_PRIVATE).edit()
                        .putBoolean("autostart", call.argument<Boolean>("enabled") ?: false).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == ACTION_TOGGLE) {
            channel?.invokeMethod("toggle", null)
        }
    }

    private fun telephony() = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_VPN)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
        }
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = packageManager
        val launch = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val flags = if (Build.VERSION.SDK_INT >= 33) PackageManager.ResolveInfoFlags.of(0L) else null
        val infos = if (flags != null) pm.queryIntentActivities(launch, flags) else @Suppress("DEPRECATION") pm.queryIntentActivities(launch, 0)
        return infos.map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .distinctBy { it.first }
            .filter { it.first != packageName }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
