package com.easyvpn.app

import android.app.Application
import android.content.Context
import com.easyvpn.app.common.GlobalState

class EasyVpnApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
