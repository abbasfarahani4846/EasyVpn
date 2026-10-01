package app.easyvpn.client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: shows the connection state and the current location, and
 * toggles the VPN with one tap (routed through MainActivity like the QS tile,
 * because the core lives in the app process).
 *
 * Dart pushes the label via the `setWidgetInfo` channel method; the service
 * refreshes the widget whenever the tunnel goes up or down.
 */
class VpnWidget : AppWidgetProvider() {
    companion object {
        private const val PREFS = "easyvpn_widget"
        const val ACTION_WIDGET_TOGGLE = "app.easyvpn.client.WIDGET_TOGGLE"

        fun setInfo(ctx: Context, connected: Boolean, node: String) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("connected", connected)
                .putString("node", node)
                .apply()
            refresh(ctx)
        }

        fun refresh(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, VpnWidget::class.java))
            if (ids.isNotEmpty()) update(ctx, mgr, ids)
        }

        private fun update(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val connected = EasyVpnService.active || prefs.getBoolean("connected", false)
            val node = prefs.getString("node", "") ?: ""
            // Broadcast intent to VpnWidget directly — does NOT launch MainActivity!
            val toggle = PendingIntent.getBroadcast(
                ctx, 11,
                Intent(ctx, VpnWidget::class.java).setAction(ACTION_WIDGET_TOGGLE),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val open = PendingIntent.getActivity(
                ctx, 12, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE,
            )
            for (id in ids) {
                val v = RemoteViews(ctx.packageName, R.layout.widget_vpn)
                v.setTextViewText(R.id.widget_state, ctx.getString(if (connected) R.string.widget_on else R.string.widget_off))
                v.setTextViewText(R.id.widget_node, if (node.isEmpty()) ctx.getString(R.string.tap_to_connect) else node)
                v.setInt(R.id.widget_root, "setBackgroundResource",
                    if (connected) R.drawable.widget_bg_on else R.drawable.widget_bg_off)
                v.setImageViewResource(R.id.widget_toggle,
                    if (connected) R.drawable.widget_power_on else R.drawable.widget_power_off)
                v.setOnClickPendingIntent(R.id.widget_toggle, toggle)
                v.setOnClickPendingIntent(R.id.widget_text, open)
                mgr.updateAppWidget(id, v)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_TOGGLE) {
            if (EasyVpnService.active) {
                EasyVpnService.stopFromActivity(context)
                MainActivity.notifyRevoked()
                refresh(context)
                return
            }
            val ch = MainActivity.channel
            if (ch != null) {
                ch.invokeMethod("toggle", null)
                refresh(context)
                return
            }
            // Fallback if process was killed
            val i = Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_TOGGLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(i)
        }
    }

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) = update(ctx, mgr, ids)
}
