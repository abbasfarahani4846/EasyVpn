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

        /** Establishes the interface and returns the raw fd (or -1). Runs on the UI thread. */
        fun establishFromActivity(ctx: Context, mtu: Int, ipv6: Boolean, include: List<String>, exclude: List<String>): Int {
            // Start the service first so a foreground notification exists; then establish.
            val intent = Intent(ctx, EasyVpnService::class.java)
            ctx.startService(intent)
            var svc = instance
            var waited = 0
            while (svc == null && waited < 2000) {
                Thread.sleep(25); waited += 25; svc = instance
            }
            return svc?.establish(mtu, ipv6, include, exclude) ?: -1
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
            .setMtu(mtu)
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
        return pfd.fd
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "VPN status", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, EasyVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val n: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("EasyVPN")
            .setContentText(getString(R.string.vpn_connected))
            .setContentIntent(open)
            .addAction(0, getString(R.string.vpn_disconnect), stop)
            .setOngoing(true)
            .build()
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
