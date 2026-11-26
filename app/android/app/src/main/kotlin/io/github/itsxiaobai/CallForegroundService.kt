package io.github.itsxiaobai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 批次 II-h：通話前景服務，避免 App 最小化/背景時被系統回收導致通話直接斷線。
 *
 * 第三十二批（人類實測回饋 2026-11-10）：
 * ① 前景服務型別改 multi-type（dataSync|camera|microphone，manifest 同步）——
 *    Android 平台規則：App 進背景後，攝影機／麥克風擷取須掛有對應型別之
 *    前景服務，否則被系統停擷取 → 對端看到「全卡住」／聽不到。
 * ② 通知即時狀態：`ring_call_status` extra＝active（通話進行中）／share
 *    （正在分享螢幕）；每次 onStartCommand 依 extra 重建通知（Dart 端
 *    ring/call_service `start`/`update` 呼叫時帶上）。
 * ③ 點通知回通話：contentIntent 深鏈 MainActivity（ring_notif_action=
 *    open_call ＋ ring_call_room_id），沿用批次十四通知動作轉發通路。
 * ④ 結束消失：Dart 端 leave時呼叫 `stop` → stopForeground(true)（既有）。
 * 草案，待人類設計定稿（通知樣式/圖示）。
 */
class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "ring_call"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(channelId, "通話中", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(channel)
        }
        val status = intent?.getStringExtra(EXTRA_STATUS) ?: STATUS_ACTIVE
        val roomId = intent?.getStringExtra(EXTRA_ROOM_ID) ?: ""
        val contentText = if (status == STATUS_SHARE) "正在分享螢幕" else "通話進行中"

        // ③ 點通知 → 回通話畫面（批次十四通路：MainActivity 讀 extras 轉發 Dart）。
        val tapIntent = Intent(this, MainActivity::class.java)
            .putExtra("ring_notif_action", "open_call")
            .putExtra("ring_notif_room_id", roomId)
        val contentIntent = PendingIntent.getActivity(
            this,
            1003, // 與批次十四通知 requestCode 錯開
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle("RING")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setContentIntent(contentIntent)
        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // multi-type（API 30+ 支援型別位元遮罩；API 34+ 起強制宣告型別）。
            startForeground(
                1002,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForeground(1002, notification)
        } else {
            startForeground(1002, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }

    companion object {
        // 批次 33 改名補完（第三十五批，人類確認 2026-11-12）：Dart 端
        // invokeMethod 傳的 key 為 'status'/'room_id'（livekit_call_manager）。
        const val EXTRA_STATUS = "status"
        const val EXTRA_ROOM_ID = "room_id"
        const val STATUS_ACTIVE = "active"
        const val STATUS_SHARE = "share"
    }
}
