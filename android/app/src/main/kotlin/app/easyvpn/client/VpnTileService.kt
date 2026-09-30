package app.easyvpn.client

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: tap opens the app and toggles the connection. */
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
