package app.easyvpn.client

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
        const val ACTION_FASTEST = "app.easyvpn.client.FASTEST"

        @Volatile var channel: MethodChannel? = null

        /** Called by [EasyVpnService] when the system revokes or the user stops the VPN. */
        fun notifyRevoked() {
            channel?.invokeMethod("vpnRevoked", null)
        }
    }

    private var pendingPrepare: MethodChannel.Result? = null

    /** Shortcut/widget action that arrived before Dart registered its handler. */
    private var pendingAction: String? = null
    private var dartReady = false

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
                "systemDns" -> result.success(systemDns())
                "establishVpn" -> {
                    val mtu = call.argument<Int>("mtu") ?: 1500
                    val ipv6 = call.argument<Boolean>("ipv6") ?: false
                    val include = call.argument<List<String>>("include") ?: emptyList()
                    val exclude = call.argument<List<String>>("exclude") ?: emptyList()
                    EasyVpnService.establishFromActivity(this, mtu, ipv6, include, exclude) { fd, err ->
                        if (fd > 0) result.success(fd) else result.error("vpn", err ?: "establish failed", null)
                    }
                }
                "stopVpn" -> {
                    EasyVpnService.stopFromActivity(this)
                    result.success(true)
                }
                "installedApps" -> result.success(installedApps())
                "ready" -> {
                    // Dart handlers are registered: replay a cold-start action.
                    dartReady = true
                    result.success(pendingAction)
                    pendingAction = null
                }
                "setWidgetInfo" -> {
                    VpnWidget.setInfo(this, call.argument<Boolean>("connected") ?: false,
                        call.argument<String>("node") ?: "")
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) result.error("update", "no path", null) else {
                        try {
                            installApk(java.io.File(path))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("update", e.message, null)
                        }
                    }
                }
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
        val method = when (intent?.action) {
            ACTION_TOGGLE -> "toggle"
            ACTION_FASTEST -> "fastest"
            else -> return
        }
        intent.action = null // do not replay on configuration changes
        if (dartReady) channel?.invokeMethod(method, null) else pendingAction = method
    }

    /** Hands a verified update APK to the system installer. */
    private fun installApk(file: java.io.File) {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                android.net.Uri.parse("package:$packageName")))
            throw IllegalStateException("allow_install")
        }
        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * DNS servers of the real (non-VPN) networks, the active one first. Android has
     * no /etc/resolv.conf, so the core needs these to resolve proxy server names.
     * Must be read before the VPN interface is established.
     */
    private fun systemDns(): List<String> {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return emptyList()
        val out = LinkedHashSet<String>()
        val nets = buildList {
            cm.activeNetwork?.let { add(it) }
            addAll(cm.allNetworks)
        }
        for (n in nets) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            cm.getLinkProperties(n)?.dnsServers?.forEach { a ->
                val h = a.hostAddress ?: return@forEach
                if (!a.isLoopbackAddress && !a.isAnyLocalAddress && !h.contains(':') && h != "172.19.0.2") out.add(h)
            }
        }
        return out.toList()
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
        dartReady = false
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
