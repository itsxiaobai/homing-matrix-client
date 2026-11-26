package io.github.itsxiaobai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM 冷啟動通知（第四十一批：人類指示「FCM ＋ UnifiedPush 通知加入」）。
 *
 * 為什麼需要原生 service：App 被**完全結束**時，Flutter 的 Dart isolate 不存在，
 * 無法顯示系統通知；本 service 由系統直接喚醒，貼一則**通用**通知
 * （「有新訊息」）並帶回 App。
 *
 * 隱私（藍圖 §二之一、PRIVACY.md §5）：
 * - Matrix pusher 一律 `format = event_id_only` → 推播內容**不含訊息內文**，
 *   本 service 也**不嘗試**解密或顯示內容；
 * - 通知文字固定為通用字串，點擊後由 App 自行 sync 並解密顯示。
 *
 * 避免重複：App 在前景時，通知由既有的本機通知流程（main_shell `_maybeNotify`）
 * 顯示；本 service 僅在 **App 不在前景**時貼通知（以 MainActivity 的
 * `isForeground` 旗標判斷）。
 */
class HomingFcmService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        // App 在前景 → 交給 Dart（既有本機通知流程），此處不貼（避免重複）。
        if (MainActivity.isForeground) {
            return
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = NOTIFY_CHANNEL_ID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(channelId) == null) {
                val ch = NotificationChannel(
                    channelId,
                    "Homing 通知",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                // 第八十六批：音效／震動偏好。
                val prefs = getSharedPreferences("homing_effects", MODE_PRIVATE)
                if (!prefs.getBoolean("sound", true)) ch.setSound(null, null)
                ch.enableVibration(prefs.getBoolean("vibration", true))
                nm.createNotificationChannel(ch)
            }
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Homing")
            .setContentText("有新訊息")
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        nm.notify(System.currentTimeMillis().toInt(), n)
    }

    companion object {
        /** 與 MainActivity 的本機通知 channel 相同（共用設定與使用者偏好）。 */
        const val NOTIFY_CHANNEL_ID = "homing/local_notifications"
    }
}
