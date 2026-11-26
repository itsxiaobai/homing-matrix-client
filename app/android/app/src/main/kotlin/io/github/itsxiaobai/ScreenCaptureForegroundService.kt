package io.github.itsxiaobai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 批次 II-b（螢幕分享 Android 14+ 修復）：MediaProjection 在 Android 14 (API 34)
 * 以上要求一個前景服務持有 mediaProjection 類型，否則 getDisplayMedia 會拋出
 * SecurityException 導致 App 閃退。此服務僅負責佔用前景服務槽位，不執行擷取。
 * 草案，待人類設計定稿（通知樣式／圖示）。
 */
class ScreenCaptureForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "ring_screen_capture"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                channelId,
                "螢幕分享",
                NotificationManager.IMPORTANCE_LOW,
            )
            nm.createNotificationChannel(channel)
        }
        val notification: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("RING")
                .setContentText("正在分享螢幕")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("RING")
                .setContentText("正在分享螢幕")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .build()
        }
        // 第 7 點（Android 15 防護）：startForeground 在無 projection consent
        // 時可能拋型別例外 → 直接閃退。此處抓住後 stopSelf，Dart 端
        // `setScreensharingEnabled` 會回報失敗（不崩 App）。
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    1001,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(1001, notification)
            }
        } catch (e: Exception) {
            stopSelf() // Dart 端 getDisplayMedia 將因無 FGS 而回錯，不閃退。
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }
}
