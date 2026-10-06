package com.easyvpn.app.service.models

data class NotificationParams(
    val title: String = "EasyVpn",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)
