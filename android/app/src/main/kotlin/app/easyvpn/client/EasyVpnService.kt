package app.easyvpn.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

/**
 * Owns the TUN device. The Go core runs in the app process (FFI) and receives the
 * file descriptor through the Dart bridge (`tun.fd` in the Start request). Routes,
 * addresses and per-app rules are fixed here by the Builder; the core only reads
 * and writes packets.
 *
 * The app's own package is disallowed, so the core's outbound sockets bypass the
 * tunnel and never loop back (no per-socket protect() callback needed).
 */
class EasyVpnService : VpnService() {
    companion object {
        const val ACTION_STOP = "app.easyvpn.client.STOP"
        private const val CHANNEL_ID = "easyvpn_vpn"
        private const val NOTIF_ID = 1

        @Volatile private var instance: EasyVpnService? = null
        @Volatile var active: Boolean = false
            private set

        @Volatile private var notifNode: String = ""
        @Volatile private var notifProtocol: String = ""
        @Volatile private var notifFlag: String = ""
        @Volatile private var notifPing: Int = 0
        @Volatile private var notifIp: String = ""

        fun updateNotificationInfo(
            node: String,
            protocol: String,
            flag: String,
            ping: Int,
            ip: String
        ) {
            if (node.isNotEmpty()) notifNode = node
            if (protocol.isNotEmpty()) notifProtocol = protocol
            if (flag.isNotEmpty()) notifFlag = flag
            if (ping > 0) notifPing = ping
            if (ip.isNotEmpty()) notifIp = ip
            instance?.updateNotification()
        }

        fun currentInfo(): Map<String, Any> {
            return mapOf(
                "active" to active,
                "node" to notifNode,
                "protocol" to notifProtocol,
                "flag" to notifFlag,
                "ping" to notifPing,
                "ip" to notifIp
            )
        }

        /**
         * Establishes the interface and reports the raw fd (or a negative code) through
         * [done]. Must NOT block the main thread: Service.onCreate() runs on it, so a
         * sleep-and-wait here would always time out on the first start.
         */
        fun establishFromActivity(
            ctx: Context, mtu: Int, ipv6: Boolean, include: List<String>, exclude: List<String>,
            done: (fd: Int, error: String?) -> Unit,
        ) {
            val handler = Handler(Looper.getMainLooper())
            fun attempt(svc: EasyVpnService) {
                val fd = runCatching { svc.establish(mtu, ipv6, include, exclude) }.getOrDefault(-1)
                if (fd > 0) done(fd, null) else done(-1, "establish_null")
            }
            instance?.let { attempt(it); return }
            ctx.startService(Intent(ctx, EasyVpnService::class.java))
            var waited = 0
            val poll = object : Runnable {
                override fun run() {
                    val svc = instance
                    when {
                        svc != null -> attempt(svc)
                        waited >= 5000 -> done(-1, "no_service")
                        else -> { waited += 50; handler.postDelayed(this, 50) }
                    }
                }
            }
            handler.post(poll)
        }

        fun stopFromActivity(ctx: Context) {
            instance?.teardown()
            ctx.stopService(Intent(ctx, EasyVpnService::class.java))
        }
    }

    private var tun: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            MainActivity.notifyRevoked()
            stopSelf()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    private fun establish(mtu: Int, ipv6: Boolean, include: List<String>, exclude: List<String>): Int {
        teardown()
        val b = Builder()
            .setSession("EasyVPN")
            .setMtu(if (mtu in 576..1500) mtu else 1500)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("172.19.0.2")
        if (ipv6) {
            b.addAddress("fdfe:dcba:9876::1", 126).addRoute("::", 0)
        }
        try {
            if (include.isNotEmpty()) {
                include.forEach { runCatching { b.addAllowedApplication(it) } }
            } else {
                runCatching { b.addDisallowedApplication(packageName) }
                exclude.forEach { runCatching { b.addDisallowedApplication(it) } }
            }
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= 29) b.setMetered(false)
        val pfd = b.establish() ?: return -1
        tun = pfd
        startForegroundCompat()
        active = true
        VpnTileService.refresh(this)
        VpnWidget.refresh(this)
        return pfd.fd
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, EasyVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)

        val flagPrefix = if (notifFlag.isNotEmpty()) "$notifFlag " else ""
        val pingSuffix = if (notifPing > 0) " (${notifPing} ms)" else ""
        val title = if (notifNode.isNotEmpty()) {
            "EasyVPN · $flagPrefix$notifNode$pingSuffix"
        } else {
            "EasyVPN · ${getString(R.string.vpn_connected)}"
        }

        val text = when {
            notifIp.isNotEmpty() -> "IP: $notifIp" + if (notifProtocol.isNotEmpty()) " · ${notifProtocol.uppercase()}" else ""
            notifProtocol.isNotEmpty() -> "${getString(R.string.vpn_connected)} · ${notifProtocol.uppercase()}"
            else -> getString(R.string.vpn_connected)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .addAction(0, getString(R.string.vpn_disconnect), stop)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    fun updateNotification() {
        if (!active) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "VPN status", NotificationManager.IMPORTANCE_LOW))
        }
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    fun teardown() {
        active = false
        runCatching { tun?.close() }
        tun = null
        VpnTileService.refresh(this)
        VpnWidget.refresh(this)
    }

    override fun onRevoke() {
        teardown()
        MainActivity.notifyRevoked()
        stopSelf()
    }

    override fun onDestroy() {
        teardown()
        instance = null
        super.onDestroy()
    }
}
