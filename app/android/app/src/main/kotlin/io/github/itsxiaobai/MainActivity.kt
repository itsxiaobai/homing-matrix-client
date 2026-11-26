package io.github.itsxiaobai

import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Intent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.content.ContentValues
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val SCREEN_CHANNEL = "homing/screen_capture"
    private val CALL_CHANNEL = "homing/call_service"
    // Suggestion #5 通知（人類決定 2026-11-05「走 local」）：本地通知 v0——
    // 零 pub 依賴（platform channel ＋ 原生 NotificationManager）。
    // 固有限制（披露）：無 FCM → App 進程未運行時無法收推播。
    private val NOTIFY_CHANNEL = "homing/local_notifications"
    // 第十八批：BLUETOOTH_CONNECT（Android 12+ API 31 起為 runtime 權限）。
    // 用途：通話「選擇音訊輸出」sheet 列舉／選擇藍牙放音裝置（AudioSwitch）。
    // 僅放音路由；不掃描、不配對。零新依賴：框架 Activity.requestPermissions
    // （同批次十二②通知權限模式）。
    private val PERM_CHANNEL = "homing/permissions"
    private val POWER_CHANNEL = "homing/power"
    // 2026-11-21：另存資料夾（SAF ACTION_OPEN_DOCUMENT_TREE）＋寫檔 channel。
    private val SAVE_CHANNEL = "homing/save_location"
    private val REQUEST_SAVE_FOLDER = 4713
    private var pendingSaveFolderResult: MethodChannel.Result? = null
    private val REQUEST_BLUETOOTH = 4712
    private var pendingBluetoothPermissionResult: MethodChannel.Result? = null

    // 批次十二②修（人類實測「通知功能沒辦法啟動」）：全 App 原無 runtime 權限
    // 請求路徑（Dart 端唯一鈕＝return false 空殼）。零新依賴：框架
    // Activity.requestPermissions（Android 官方 API，非 androidx）。
    private val REQUEST_NOTIFICATIONS = 4711
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    // 批次十四：原生 Notification 指向 Dart 的 MethodChannel（儲存於屬性，以便
    // onNewIntent／onCreate 就緒後把通知動作（已讀／回覆／開啟房間）發給 Dart）。
    private lateinit var notifyChannel: MethodChannel

    // 批次十四：App 被殺後，透過 PendingIntent 喚起 MainActivity 時，onCreate
    // 讀取的通知動作 extra 會暫存於此；configureFlutterEngine 就緒後再發給 Dart。
    private var pendingNotifAction: String? = null
    private var pendingNotifRoomId: String? = null
    private var pendingNotifReplyText: String? = null

    // 第二十六批：外部「檔案型」分享（ACTION_SEND／ACTION_SEND_MULTIPLE）。
    // Manifest 既有 SEND filter 但批十三只接 app_links 文字 uri → intent 無人
    // 消費。本批 `ring/share` channel：onCreate 冷啟動分享（未登入即停在
    // native 暫存＝人類拍板「登入後自動開 picker」）、onNewIntent 熱啟動即推。
    // 檔案＝ContentResolver 複製到 cacheDir（intent 自帶讀取授權，零新權限）。
    private val SHARE_CHANNEL = "homing/share"
    private lateinit var shareChannel: MethodChannel
    private var pendingSharePayload: Map<String, Any?>? = null

    // 第四十一批：App 是否在前台（供 FCM 冷啟動通知判斷，避免與前景的
    // 本機通知重複）。由 onResume／onPause 維護。
    companion object {
        @JvmStatic
        var isForeground: Boolean = false
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
    }

    override fun onPause() {
        super.onPause()
        isForeground = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 批次十四：讀取通知動作 PendingIntent 的 extra（App 被殺後喚起）。
        val intent = this.intent
        val action = intent.getStringExtra("ring_notif_action")
        if (action != null) {
            pendingNotifAction = action
            pendingNotifRoomId = intent.getStringExtra("ring_room_id")
            pendingNotifReplyText = intent.getStringExtra("ring_reply_text")
        }
        // 第二十六批：僅真冷啟動解析分享 intent（activity 重建不重複暫存，
        // 避免 picker 重複彈出）。
        if (savedInstanceState == null) {
            pendingSharePayload = readShareIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("ring_notif_action")
        if (action != null) {
            pendingNotifAction = action
            pendingNotifRoomId = intent.getStringExtra("ring_room_id")
            pendingNotifReplyText = intent.getStringExtra("ring_reply_text")
            // onNewIntent 在 onCreate 之後，FlutterEngine 已就緒，直接發送 Dart。
            sendNotificationActionToDart(action, pendingNotifRoomId!!, pendingNotifReplyText)
            pendingNotifAction = null
            pendingNotifRoomId = null
            pendingNotifReplyText = null
        }
        // 第二十六批：熱啟動分享 → Dart（channel 已就緒即推；未就緒則落到
        // native 暫存，get_initial 仍可取回）。
        val sharePayload = readShareIntent(intent)
        if (sharePayload != null) {
            try {
                shareChannel.invokeMethod("share", sharePayload)
            } catch (e: Exception) {
                if (pendingSharePayload == null) {
                    pendingSharePayload = sharePayload
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notifyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL)
        // 第二十六批：外部分享 channel（get_initial＝讀冷啟動暫存即清）。
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "get_initial" -> {
                    val payload = pendingSharePayload
                    pendingSharePayload = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }
        // 第八十二批：電源使用限制／網路設定（預約訊息背景準點用）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "is_ignoring_battery" -> {
                    val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "request_ignore_battery" -> {
                    try {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        )
                        intent.data = android.net.Uri.parse("package:$packageName")
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "open_network_settings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_WIRELESS_SETTINGS)
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 2026-11-21：另存資料夾——首次選資料夾並取得永久 Uri 權限，之後直接寫入。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pick_folder" -> {
                    pendingSaveFolderResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                        startActivityForResult(intent, REQUEST_SAVE_FOLDER)
                    } catch (e: Exception) {
                        pendingSaveFolderResult = null
                        result.error("PICK_FAILED", e.message, null)
                    }
                }
                "save_bytes" -> {
                    try {
                        val args = call.arguments as Map<*, *>
                        val treeUri = Uri.parse(args["uri"] as String)
                        val name = (args["name"] as String)
                            .replace(Regex("[/\\\\\n\r\t]"), "_")
                        val mime = args["mime"] as? String ?: "application/octet-stream"
                        val bytes = args["bytes"] as ByteArray
                        val dirUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri, DocumentsContract.getTreeDocumentId(treeUri)
                        )
                        val fileUri = DocumentsContract.createDocument(
                            contentResolver, dirUri, mime, name
                        ) ?: throw Exception("createDocument 回 null")
                        val fd: ParcelFileDescriptor? =
                            contentResolver.openFileDescriptor(fileUri, "w")
                        if (fd == null) throw Exception("openFileDescriptor 回 null")
                        fd.use { pfd ->
                            java.io.FileOutputStream(pfd.fileDescriptor).use { out ->
                                out.write(bytes)
                            }
                        }
                        result.success(mapOf("name" to name, "uri" to fileUri.toString()))
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 第十八批：通話藍牙放音裝置權限（BLUETOOTH_CONNECT，Android 12+）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "check_bluetooth" -> {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                            checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    )
                }
                "request_bluetooth" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    // 已永久拒絕（「不再詢問」）→ 系統不彈框直接回拒 → 回 false；
                    // Dart 端據此僅列內建裝置＋提示（不重試轟炸）。
                    pendingBluetoothPermissionResult = result
                    try {
                        requestPermissions(
                            arrayOf(android.Manifest.permission.BLUETOOTH_CONNECT),
                            REQUEST_BLUETOOTH,
                        )
                    } catch (e: Exception) {
                        pendingBluetoothPermissionResult = null
                        result.error("REQUEST_FAILED", e.message, null)
                    }
                }
                "audio_diagnostics" -> {
                    // 第十九批：②-A 決定性診斷（臨時除錯，根因定案後的下批移除）
                    // ——唯讀 ground truth：①BLUETOOTH_CONNECT 授權狀態（同
                    // check_bluetooth 的版本守衛）；②AudioManager.getDevices
                    // (GET_DEVICES_OUTPUTS) 在 App 進程內的原始輸出清單；
                    // ③Android 12+ 追加：當前溝通裝置／可用溝通裝置候選／音訊
                    // 模式（setCommunicationDevice 式修法的判讀資料）。只讀不寫
                    // ——底層狀態不受影響；零新 OS 權限、零 pub 依賴。
                    try {
                        val am = getSystemService(android.content.Context.AUDIO_SERVICE) as
                            android.media.AudioManager
                        val outputDevices = ArrayList<Map<String, String>>()
                        for (d in am.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS)) {
                            outputDevices.add(
                                mapOf(
                                    "name" to (d.productName?.toString() ?: ""),
                                    "typeName" to audioTypeName(d.type),
                                ),
                            )
                        }
                        val diag = HashMap<String, Any?>()
                        // 第二十批：修第十九批遺漏——上一版漏了這行賦值，
                        // 診斷列因此顯示「原始輸出清單: 無資料」（清單建了
                        // 卻沒放進回傳 map）。
                        diag["outputDevices"] = outputDevices
                        diag["permissionGranted"] =
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                                checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                                android.content.pm.PackageManager.PERMISSION_GRANTED
                        diag["audioMode"] = audioModeName(am.mode)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val communicationDevices = ArrayList<Map<String, String>>()
                            for (d in am.getAvailableCommunicationDevices()) {
                                communicationDevices.add(
                                    mapOf(
                                        "name" to (d.productName?.toString() ?: ""),
                                        "typeName" to audioTypeName(d.type),
                                    ),
                                )
                            }
                            diag["communicationDevices"] = communicationDevices
                            val cd = am.getCommunicationDevice()
                            diag["communicationDevice"] = if (cd != null) {
                                mapOf(
                                    "name" to (cd.productName?.toString() ?: ""),
                                    "typeName" to audioTypeName(cd.type),
                                )
                            } else {
                                null
                            }
                        }
                        result.success(diag)
                    } catch (e: Exception) {
                        result.error("DIAG_FAILED", e.message, null)
                    }
                }
                "list_audio_outputs" -> {
                    // 第二十批：②-A 根因修（人類批准 2026-11-08「是」）——繞過
                    // AudioSwitch fork 清單（診斷證實其 `registerAudioDeviceCallback`
                    // 清單與系統脫節：`getAvailableCommunicationDevices()` 有筆電
                    // 耳機、AudioSwitch 列舉永缺）。Android 12+ 回傳官方
                    // `AudioManager.getAvailableCommunicationDevices()`（＝可供
                    // setCommunicationDevice 的裝置集合，含當前選中的
                    // isCurrent）；Android 11 以下 supported=false（Dart 端
                    // 維持 1.6.3 舊路徑）。零新權限（BLUETOOTH_CONNECT 既有）。
                    try {
                        val am = getSystemService(android.content.Context.AUDIO_SERVICE) as
                            android.media.AudioManager
                        val devices = ArrayList<Map<String, Any?>>()
                        var supported = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            supported = true
                            val current = am.getCommunicationDevice()
                            for (d in am.getAvailableCommunicationDevices()) {
                                devices.add(
                                    mapOf(
                                        "name" to (d.productName?.toString() ?: ""),
                                        "typeName" to audioTypeName(d.type),
                                        "isCurrent" to (current != null && current.id == d.id),
                                    ),
                                )
                            }
                        }
                        result.success(
                            mapOf(
                                "supported" to supported,
                                "devices" to devices,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("LIST_FAILED", e.message, null)
                    }
                }
                "set_communication_device" -> {
                    // 第二十批：②-A 根因修——官方 `AudioManager.setCommunicationDevice`
                    // (Android 12+)：依 typeName 匹配溝通裝置、套用後「回讀當前
                    // 溝通裝置型別」二次驗證（避免無聲失敗；裝置斷線→找不到 →
                    // false）。目標裝置匹配不到／早於 Android 12 → false。
                    try {
                        val args = call.arguments as Map<*, *>
                        val typeName = args["typeName"] as? String
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || typeName == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val am = getSystemService(android.content.Context.AUDIO_SERVICE) as
                            android.media.AudioManager
                        val target = am.getAvailableCommunicationDevices()
                            .firstOrNull { audioTypeName(it.type) == typeName }
                        if (target == null) {
                            // 系統清單裡已無此型別（耳機斷線／退場）→ 明確 false。
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val ok = am.setCommunicationDevice(target)
                        val verified = ok &&
                            am.getCommunicationDevice()?.let { audioTypeName(it.type) == typeName } == true
                        result.success(verified)
                    } catch (e: Exception) {
                        result.error("SET_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        notifyChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // 第八十六批：音效／震動偏好 → 存 SharedPreferences 並重建 channel。
                "set_effects" -> {
                    try {
                        val args = call.arguments as Map<*, *>
                        val prefs = getSharedPreferences("homing_effects", MODE_PRIVATE)
                        prefs.edit()
                            .putBoolean("sound", args["sound"] as? Boolean ?: true)
                            .putBoolean("vibration", args["vibration"] as? Boolean ?: true)
                            .apply()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                            val ch = NotificationChannel(
                                "ring_messages", "RING 訊息",
                                NotificationManager.IMPORTANCE_DEFAULT
                            )
                            if (!(args["sound"] as? Boolean ?: true)) ch.setSound(null, null)
                            ch.enableVibration(args["vibration"] as? Boolean ?: true)
                            nm.createNotificationChannel(ch)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "show" -> {
                    try {
                        val args = call.arguments as Map<*, *>
                        val title = args["title"] as? String ?: "RING" // 定稿待人類
                        val body = args["body"] as? String ?: ""
                        val roomKey = args["room"] as? String ?: "ring"
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val ch = NotificationChannel(
                                "ring_messages",
                                "RING 訊息", // 文案草案，待人類定稿
                                NotificationManager.IMPORTANCE_DEFAULT
                            )
                            // 第八十六批：音效／震動偏好（SharedPreferences）。
                            val prefs = getSharedPreferences("homing_effects", MODE_PRIVATE)
                            val soundOn = prefs.getBoolean("sound", true)
                            val vibrationOn = prefs.getBoolean("vibration", true)
                            if (!soundOn) ch.setSound(null, null)
                            ch.enableVibration(vibrationOn)
                            nm.createNotificationChannel(ch)
                        }
                        // Android 13+（TIRAMISU）需 POST_NOTIFICATIONS runtime 權限；
                        // 未授權 → 回 false（Dart 端靜默不重試；權限畫面請_user 自行開啟）。
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        // 批次十四：點開通知進對應聊天室；加「已讀／回覆」兩個
                        // 動作按鈕，不須進軟體即可操作（Android 通知欄直接回覆）。
                        val flags = pendingIntentFlags()
                        val openIntent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            putExtra("ring_notif_action", "open")
                            putExtra("ring_room_id", roomKey)
                        }
                        val openPending = PendingIntent.getActivity(
                            this, 10000 + roomKey.hashCode(), openIntent, flags,
                        )
                        val readIntent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            putExtra("ring_notif_action", "read")
                            putExtra("ring_room_id", roomKey)
                        }
                        val readPending = PendingIntent.getActivity(
                            this, 10010 + roomKey.hashCode(), readIntent, flags,
                        )
                        val replyInput = RemoteInput.Builder("ring_reply_text")
                            .setLabel("回覆") // 文案草案
                            .build()
                        val replyIntent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            putExtra("ring_notif_action", "reply")
                            putExtra("ring_room_id", roomKey)
                        }
                        val replyPending = PendingIntent.getActivity(
                            this, 10020 + roomKey.hashCode(), replyIntent, flags,
                        )
                        val readAction = Notification.Action.Builder(
                            android.R.drawable.ic_menu_info_details, "已讀", // 文案草案
                            readPending,
                        ).build()
                        val replyAction = Notification.Action.Builder(
                            android.R.drawable.ic_menu_send, "回覆", // 文案草案
                            replyPending,
                        ).addRemoteInput(replyInput).build()
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, "ring_messages")
                        } else {
                            @Suppress("DEPRECATION") Notification.Builder(this)
                        }
                        builder.setSmallIcon(R.mipmap.ic_launcher)
                            .setContentTitle(title)
                            .setContentText(body)
                            .setAutoCancel(true)
                            .setContentIntent(openPending)
                            .addAction(readAction)
                            .addAction(replyAction)
                        nm.notify(roomKey.hashCode(), builder.build())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHOW_FAILED", e.message, null)
                    }
                }
                // 批次十二②修：查詢／請求 POST_NOTIFICATIONS（Android 13+）。
                // <TIRAMISU 無此 runtime 權限 → 直接 true。
                "check_permission" -> {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    )
                }
                "request_permission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    // 已永久拒絕（「不再詢問」）時系統不彈框、直接回拒——Dart 端
                    // 以提示代替（請使用者到系統設定開啟）。
                    pendingNotificationPermissionResult = result
                    try {
                        requestPermissions(
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_NOTIFICATIONS,
                        )
                    } catch (e: Exception) {
                        pendingNotificationPermissionResult = null
                        result.error("REQUEST_FAILED", e.message, null)
                    }
                }
                "cancel" -> {
                    val args = call.arguments as Map<*, *>
                    val roomKey = args["room"] as? String ?: "ring"
                    try {
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(roomKey.hashCode())
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 批次十四：onCreate 緩下來的通知動作，現在 FlutterEngine 已就緒，發給 Dart。
        if (pendingNotifAction != null) {
            sendNotificationActionToDart(
                pendingNotifAction!!,
                pendingNotifRoomId!!,
                pendingNotifReplyText,
            )
            pendingNotifAction = null
            pendingNotifRoomId = null
            pendingNotifReplyText = null
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, ScreenCaptureForegroundService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, ScreenCaptureForegroundService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, CallForegroundService::class.java)
                        // 第三十二批：args 可為 Map {status:'active'|'share', room_id:String}
                        // （舊呼叫端不傳參＝預設 active）；通知依狀態即時更新。
                        val args = call.arguments
                        if (args is Map<*, *>) {
                            intent.putExtra(
                                CallForegroundService.EXTRA_STATUS,
                                args["status"] as? String ?: CallForegroundService.STATUS_ACTIVE,
                            )
                            intent.putExtra(
                                CallForegroundService.EXTRA_ROOM_ID,
                                args["room_id"] as? String ?: "",
                            )
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "update" -> {
                    // 第三十二批：狀態即時更新（startService 觸發 onStartCommand 重建
                    // 通知；前景服務已在運行時 startService 合法）。
                    try {
                        val args = call.arguments
                        val intent = Intent(this, CallForegroundService::class.java)
                        if (args is Map<*, *>) {
                            intent.putExtra(
                                CallForegroundService.EXTRA_STATUS,
                                args["status"] as? String ?: CallForegroundService.STATUS_ACTIVE,
                            )
                            intent.putExtra(
                                CallForegroundService.EXTRA_ROOM_ID,
                                args["room_id"] as? String ?: "",
                            )
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UPDATE_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, CallForegroundService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // 2026-11-21：SAF 選資料夾結果 → 取永久權限並回傳 Uri 給 Dart 存 kv。
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE_FOLDER) return
        val pending = pendingSaveFolderResult
        pendingSaveFolderResult = null
        if (resultCode != android.app.Activity.RESULT_OK || data?.data == null) {
            pending?.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            pending?.success(uri.toString())
        } catch (e: Exception) {
            pending?.error("PERSIST_FAILED", e.message, null)
        }
    }

    // 批次十二②修：通知權限請求結果回傳 Dart（pendingResult；不阻塞 Flutter
    // 其他權限 callback——先交給 super）。第十八批新增 REQUEST_BLUETOOTH 分支。
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            REQUEST_NOTIFICATIONS -> {
                val pending = pendingNotificationPermissionResult
                pendingNotificationPermissionResult = null
                try {
                    pending?.success(granted)
                } catch (e: Exception) {
                    // result 已被 Dart 端放棄（觸發逾時等）——靜默。
                }
            }
            REQUEST_BLUETOOTH -> {
                val pending = pendingBluetoothPermissionResult
                pendingBluetoothPermissionResult = null
                try {
                    pending?.success(granted)
                } catch (e: Exception) {
                    // result 已被 Dart 端放棄（觸發逾時等）——靜默。
                }
            }
        }
    }

    // 批次十四：PendingIntent 旗標（Android 12+ 需 FLAG_IMMUTABLE；更低版本忽略）。
    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    // 批次十四：把通知動作（已讀／回覆／開啟房間）傳給 Dart 端處理。
    private fun sendNotificationActionToDart(
        action: String,
        roomId: String?,
        replyText: String?,
    ) {
        try {
            notifyChannel.invokeMethod("notification_action", mapOf(
                "action" to action,
                "room_id" to roomId,
                "reply_text" to replyText,
            ))
        } catch (e: Exception) {
            // channel 尚未就緒等情況靜默（configureFlutterEngine 裡的 pending
            // 機制已補發；不影響後續）。
        }
    }

    // 第十九批：AudioDeviceInfo 型別常數 → 簡短識別名（audio_diagnostics 顯示
    // 用；未列出的型別回 `type_<n>`，不影響判讀）。常數在 compileSdk 36皆有
    // 定義，minSdk 24 以下機型不會產生 BLE_*／SPEAKER_SAFE 值。
    private fun audioTypeName(type: Int): String = when (type) {
        0 -> "unknown"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "builtin_earpiece"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "builtin_speaker"
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired_headset"
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired_headphones"
        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth_sco"
        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth_a2dp"
        android.media.AudioDeviceInfo.TYPE_HDMI -> "hdmi"
        android.media.AudioDeviceInfo.TYPE_USB_DEVICE -> "usb_device"
        android.media.AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb_accessory"
        android.media.AudioDeviceInfo.TYPE_USB_HEADSET -> "usb_headset"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "builtin_speaker_safe"
        android.media.AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> "remote_submix"
        android.media.AudioDeviceInfo.TYPE_BLE_HEADSET -> "ble_headset"
        android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER -> "ble_speaker"
        else -> "type_$type"
    }

    // 第十九批：AudioManager.mode 整數 → 簡短識別名（audio_diagnostics 顯示用）。
    private fun audioModeName(mode: Int): String = when (mode) {
        android.media.AudioManager.MODE_NORMAL -> "NORMAL"
        android.media.AudioManager.MODE_RINGTONE -> "RINGTONE"
        android.media.AudioManager.MODE_IN_CALL -> "IN_CALL"
        android.media.AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION"
        android.media.AudioManager.MODE_CALL_SCREENING -> "CALL_SCREENING"
        else -> "mode_$mode"
    }

    // ─── 第二十六批：外部分享 intent 解析 ───

    // 解析 ACTION_SEND／SEND_MULTIPLE：文字＝EXTRA_TEXT；檔案＝EXTRA_STREAM
    //（單一 Uri 或 ArrayList<Uri>）逐個複製到 cacheDir/ring_share/ 後回傳
    // {path,name,mimeType,sizeBytes} 清單。字串訊息與檔案可並存。
    private fun readShareIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) {
            return null
        }
        val isSend = intent.action == Intent.ACTION_SEND ||
            intent.action == Intent.ACTION_SEND_MULTIPLE
        if (!isSend) {
            return null
        }
        val payload = HashMap<String, Any?>()
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrEmpty()) {
            payload["text"] = text
        }
        val uris = ArrayList<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (uri != null) {
                uris.add(uri)
            }
        } else {
            val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(
                    Intent.EXTRA_STREAM,
                    Uri::class.java,
                )
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (list != null) {
                uris.addAll(list)
            }
        }
        val files = ArrayList<Map<String, Any?>>()
        var index = 0
        for (uri in uris) {
            val file = shareFileToCache(uri, index)
            if (file != null) {
                files.add(file)
                index++
            }
        }
        if (files.isNotEmpty()) {
            payload["files"] = files
        }
        return if (payload.isEmpty()) null else payload
    }

    // content:// → cacheDir 複製（intent 已帶讀取授權；失敗逐檔回 null 跳過）。
    private fun shareFileToCache(uri: Uri, index: Int): Map<String, Any?>? {
        return try {
            val resolver = contentResolver
            val mime = resolver.getType(uri) ?: "application/octet-stream"
            val display = queryDisplayName(uri)
            val dir = File(cacheDir, "ring_share")
            dir.mkdirs()
            val safe =
                (display ?: uri.lastPathSegment ?: "ring_share_$index")
                    .replace(Regex("[/\\\\\n\r\t]"), "_")
            val out = File(dir, safe)
            val input = resolver.openInputStream(uri) ?: return null
            input.use { ins ->
                FileOutputStream(out).use { output -> ins.copyTo(output) }
            }
            mapOf(
                "path" to out.absolutePath,
                "name" to (display ?: out.name),
                "mimeType" to mime,
                "sizeBytes" to out.length(),
            )
        } catch (e: Exception) {
            null
        }
    }

    // 顯示檔名（OpenableColumns.DISPLAY_NAME；查不到回 null 由 lastPathSegment 頂）。
    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
        } catch (e: Exception) {
            null
        }
    }
}
