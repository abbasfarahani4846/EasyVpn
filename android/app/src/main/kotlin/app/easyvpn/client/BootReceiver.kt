package app.easyvpn.client

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * After boot, if "start with the device" is enabled, posts a one-tap notification
 * that opens the app and connects. (Android 10+ forbids starting activities from
 * the background, and the core lives in the Flutter process, so a tap is required.)
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!ctx.getSharedPreferences("easyvpn", Context.MODE_PRIVATE).getBoolean("autostart", false)) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel("easyvpn_boot", "Start", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(
            ctx, 3, Intent(ctx, MainActivity::class.java).setAction(MainActivity.ACTION_TOGGLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE
        )
        nm.notify(
            2,
            NotificationCompat.Builder(ctx, "easyvpn_boot")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle("EasyVPN")
                .setContentText(ctx.getString(R.string.tap_to_connect))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }
}
