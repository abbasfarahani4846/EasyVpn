package app.easyvpn.client

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: tap toggles the connection directly without opening the app. */
class VpnTileService : TileService() {
    companion object {
        fun refresh(ctx: Context) {
            if (Build.VERSION.SDK_INT >= 24) {
                requestListeningState(ctx, ComponentName(ctx, VpnTileService::class.java))
            }
        }
    }

    override fun onStartListening() {
        qsTile?.apply {
            state = if (EasyVpnService.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = "EasyVPN"
            updateTile()
        }
    }

    override fun onClick() {
        if (EasyVpnService.active) {
            // Disconnect immediately in background without opening the app
            EasyVpnService.stopFromActivity(this)
            MainActivity.notifyRevoked()
            onStartListening()
            return
        }

        // To connect without opening the app, invoke live channel if app process is alive
        val ch = MainActivity.channel
        if (ch != null) {
            ch.invokeMethod("toggle", null)
            onStartListening()
            return
        }

        // Fallback: If app process is dead, start MainActivity to initialize
        val i = Intent(this, MainActivity::class.java)
            .setAction(MainActivity.ACTION_TOGGLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(android.app.PendingIntent.getActivity(this, 2, i, android.app.PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(i)
        }
    }
}
