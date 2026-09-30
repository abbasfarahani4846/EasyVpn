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
            val toggle = PendingIntent.getActivity(
                ctx, 11,
                Intent(ctx, MainActivity::class.java)
                    .setAction(MainActivity.ACTION_TOGGLE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
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

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) = update(ctx, mgr, ids)
}
