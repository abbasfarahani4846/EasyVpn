package com.easyvpn.app.core

import androidx.annotation.Keep

@Keep
interface InvokeInterface {
    fun onResult(result: ByteArray?)
}