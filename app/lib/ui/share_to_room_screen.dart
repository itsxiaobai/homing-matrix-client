// 批十三（人類批准 2026-11-07）：外部分享「Send to」房間選擇器骨架。
// 參考（僅參考結構、不仿製品牌樣式）：EX 截圖
// LINE_ref/new_ref/share_EX/Screenshot_20261102-222200_labeled.png ——
// 搜尋列＋房間列表（avatar＋名稱＋alias）＋**多選 checkbox**＋右上 Send。
// 依 AGENTS.md UI 規則＝草案／最小樣式（主題色），待人類定稿。
// 第二十六批（人類拍板 2026-11-08）：接收載體升級為 SharePayload（文字／
// 檔案清單，見 share_receiver.dart）。檔案＝與聊天頁附件**同一官方送出鏈**：
// 圖片 `prepareImageInBackground`（背景 isolate 下採樣＋縮圖）→ 加密房經
// SDK 官方 `encryptFileInBackground` → `buildUploadFile` →
// `Room.sendFileEvent`（加密由 SDK 官方 sendFileEvent 內部路由，App 端零
// 自寫演算法）；429 退避＝`sendWithRateLimitRetry`；離線失敗＝
// `OfflineQueue.enqueueAttachment`（同批四規則：too-big 不入列）。文字＝
// `Room.sendTextEvent`。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../media_upload.dart';
import '../offline_queue.dart';
import '../share_receiver.dart';
import 'chat_screen.dart' show sendWithRateLimitRetry;

class ShareToRoomScreen extends StatefulWidget {
  const ShareToRoomScreen({
    required this.client,
    required this.payload,
    this.preselectedRoomIds,
    this.title,
    super.key,
  });

  final Client client;

  /// 分享內容（文字／檔案清單；二十六批起）。
  final SharePayload payload;

  /// 第三十五批 #6（緊急求助流程重用）：預先勾選的房間 id
  /// （緊急聯絡人／所有人預選；使用者仍可增刪——「發到哪裡讓使用者決定」）。
  final Set<String>? preselectedRoomIds;

  /// 第三十五批 #6：頂列標題覆寫（緊急流程＝「選擇要通知的對象」；
  /// null＝既有「分享到聊天室」）。
  final String? title;

  @override
  State<ShareToRoomScreen> createState() => _ShareToRoomScreenState();
}

class _ShareToRoomScreenState extends State<ShareToRoomScreen> {
  final Set<String> _selectedRoomIds = {};
  String _query = '';
  bool _sending = false;
  int _deliveredCount = 0;

  @override
  void initState() {
    super.initState();
    // 第三十五批 #6：預選（僅保留實際存在的房間 id）。
    if (widget.preselectedRoomIds != null) {
      final existing = widget.client.rooms.map((r) => r.id).toSet();
      _selectedRoomIds.addAll(
        widget.preselectedRoomIds!.where(existing.contains),
      );
    }
  }

  /// 顯示名稱（同 rooms_screen 模式：官方 getLocalizedDisplayname →
  /// name → id 逐級退路；物件拋錯照退）。
  String _roomTitle(Room room) {
    try {
      final display = room.getLocalizedDisplayname();
      if (display.isEmpty || display == 'Empty chat') {
        final name = room.name;
        return name.isNotEmpty ? name : room.id;
      }
      return display;
    } catch (_) {
      final name = room.name;
      return name.isNotEmpty ? name : room.id;
    }
  }

  /// alias 列（EX 欄位；無 alias → 顯示 room.id）。
  String _roomSubtitle(Room room) {
    try {
      // 官方 Room.canonicalAlias（room.dart L313）＝非空 String；無 alias 為 ''。
      final alias = room.canonicalAlias;
      if (alias.isNotEmpty) {
        return alias;
      }
    } catch (_) {}
    return room.id;
  }

  /// 頭像 URL（存取可能因 db 未初始化拋錯 → null 圓字 fallback）。
  Uri? _roomAvatar(Room room) {
    try {
      return room.avatar;
    } catch (_) {
      return null;
    }
  }

  /// 右上「送出」（EX 欄位）：對選中房間逐一送出（[deliverTo]，官方 API）；
  /// 部分失敗不中斷其餘（回報失敗清單）。
  Future<void> _send() async {
    if (_sending || _selectedRoomIds.isEmpty) {
      return;
    }
    final text = widget.payload.text;
    final files = widget.payload.files;
    final targets = widget.client.rooms
        .where((room) => _selectedRoomIds.contains(room.id))
        .toList();
    if (targets.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _deliveredCount = 0;
    });
    final failed = <String>[];
    final delivered = <String>[];
    try {
      for (final room in targets) {
        final title = _roomTitle(room);
        try {
          await _deliverTo(room, text: text, files: files);
          _deliveredCount++;
          delivered.add(title);
        } catch (e) {
          failed.add(title);
        }
        if (mounted) {
          setState(() {});
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
    if (!mounted) {
      return;
    }
    final okCount = delivered.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          // 文案草案
          failed.isEmpty
              ? '已分享到 $okCount 間聊天室'
              : '已分享到 $okCount 間；失敗：${failed.join('、')}',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  /// 對單一目標房間送出全部分享內容。官方鏈（見檔頭）。
  Future<void> _deliverTo(Room room, {String? text, List<SharedItem> files = const []}) async {
    if (text != null && text.isNotEmpty) {
      await sendWithRateLimitRetry(() => room.sendTextEvent(text));
    }
    for (final item in files) {
      final bytes = await _readSharedFile(item);
      final name = item.name;
      final isImage = isImageFileName(name);
      final isVideo = isVideoFileName(name);
      ImagePreparation? imagePrep;
      Uint8List uploadBytes = bytes;
      int? uploadWidth;
      int? uploadHeight;
      String? uploadMime;
      if (isImage) {
        imagePrep = await prepareImageInBackground(bytes: bytes, name: name);
        // 慢傳修復（人類批准 2026-11-06）：上傳 bytes 用背景 isolate 下採樣
        // 版本；JPEG/PNG mediType 覆寫後送 m.image。
        uploadBytes = imagePrep?.upload?.bytes ?? bytes;
        uploadWidth = imagePrep?.upload?.width ?? imagePrep?.width;
        uploadHeight = imagePrep?.upload?.height ?? imagePrep?.height;
        uploadMime = imagePrep?.upload?.mimeType;
      }
      // 加密房＝SDK 官方 encryptFile（Prime in background isolate 即可）。App
      // 端零自寫加密演算法；未加密房＝不加密（與 SDK 行為／聊天頁一致）。
      EncryptedFile? encrypted;
      if (room.encrypted) {
        encrypted = await encryptFileInBackground(uploadBytes);
      }
      final file = buildUploadFile(
        bytes: uploadBytes,
        name: name,
        isImage: isImage,
        isVideo: isVideo,
        image: imagePrep,
        imageWidth: uploadWidth,
        imageHeight: uploadHeight,
        imageMimeType: uploadMime,
        encrypted: encrypted,
      );
      try {
        // 429 退避重試（同聊天頁）：事件未落地前重試不會重複；txid 自帶。
        final txid = room.client.generateUniqueTransactionId();
        await sendWithRateLimitRetry(
          () => room.sendFileEvent(
            file,
            thumbnail: imagePrep?.thumbnail,
            txid: txid,
          ),
        );
      } on FileTooBigMatrixException {
        // too-big → 不入離線佇列（檔案本來就送不上該伺服器）；上拋給
        // 房間層計為失敗（本批不做每檔進度 UI，草案待人類定稿）。
        rethrow;
      } catch (e) {
        // 離線佇列（批四規則）：非 too-big 附件送出失敗 → 入列；連線恢復後
        // OfflineQueue.drain 依序送出（CACHE 佇列報錯情況照本源處理）。
        final enqueued = await OfflineQueue.enqueueAttachment(
          roomId: room.id,
          name: name,
          bytes: uploadBytes,
          path: item.path,
        );
        if (enqueued < 0) {
          rethrow; // 無路徑且 > BLOB 上限 → 明確失敗（不吞錯）。
        }
      }
    }
  }

  /// 讀取分享檔（cacheDir 複製檔）bytes；讀失敗視同該房失敗。
  Future<Uint8List> _readSharedFile(SharedItem item) {
    return File(item.path).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    // 房間清單：官方 client.rooms（含搜尋過濾；名稱／alias 都比對）。
    final rooms = widget.client.rooms.where((room) {
      if (_query.isEmpty) {
        return true;
      }
      final q = _query.toLowerCase();
      return _roomTitle(room).toLowerCase().contains(q) ||
          _roomSubtitle(room).toLowerCase().contains(q);
    }).toList();
    final fileCount = widget.payload.files.length;
    final hasText = widget.payload.text != null &&
        widget.payload.text!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // 文案草案（EX 欄位名；第三十五批 #6 緊急流程覆寫）。
        title: Text(widget.title ?? '分享到聊天室'),
        actions: [
          TextButton(
            // EX 欄位：右上 Send（骨架＝TextButton；樣式待人類定稿）。
            onPressed: (_sending || _selectedRoomIds.isEmpty) ? null : _send,
            child: Text(
              _selectedRoomIds.isEmpty
                  ? '送出' // 文案草案
                  : '送出（${_selectedRoomIds.length}）', // 文案草案
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                // EX 欄位：搜尋列。
                hintText: '搜尋', // 文案草案
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          // 檔案／文字預計送出內容（草案：數量摘要，不預載檔案預覽圖）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                fileCount > 0
                    ? (hasText
                        ? '$fileCount 個檔案＋文字 · 共 ${widget.payload.files.fold(0, (a, f) => a + f.sizeBytes)} bytes'
                        : '$fileCount 個檔案 · 共 ${widget.payload.files.fold(0, (a, f) => a + f.sizeBytes)} bytes')
                    : (hasText ? widget.payload.text! : '沒有可分享的內容'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: rooms.isEmpty
                ? const Center(
                    child: Text('沒有可分享的聊天室'), // 文案草案
                  )
                : ListView.builder(
                    itemCount: rooms.length,
                    itemBuilder: (context, i) {
                      final room = rooms[i];
                      final selected = _selectedRoomIds.contains(room.id);
                      return ListTile(
                        leading: _ShareRoomAvatar(
                          title: _roomTitle(room),
                          avatar: _roomAvatar(room),
                          client: widget.client,
                        ),
                        // EX 欄位：名稱＋alias。
                        title: Text(_roomTitle(room), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          _roomSubtitle(room),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Checkbox(
                          // EX 欄位：多選 checkbox。
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedRoomIds.add(room.id);
                            } else {
                              _selectedRoomIds.remove(room.id);
                            }
                          }),
                        ),
                        // 整列可選（checkbox 同步，多選）。
                        onTap: () => setState(() {
                          if (selected) {
                            _selectedRoomIds.remove(room.id);
                          } else {
                            _selectedRoomIds.add(room.id);
                          }
                        }),
                      );
                    },
                  ),
          ),
          if (_sending)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                // 文案草案（進度＝已成功房間數，不逐檔細節）。
                '送出中…（$_deliveredCount完成）', // 文案草案
              ),
            ),
        ],
      ),
    );
  }
}

/// 房間頭像圓（骨架；同 rooms_screen _RoomAvatar 模式：官方
/// `Uri.getThumbnailUri`＋authenticated media；失敗退首字）。
class _ShareRoomAvatar extends StatelessWidget {
  const _ShareRoomAvatar({
    required this.title,
    required this.avatar,
    required this.client,
  });

  final String title;
  final Uri? avatar;
  final Client client;

  @override
  Widget build(BuildContext context) {
    final first = title.runes.isEmpty ? null : String.fromCharCode(title.runes.first);
    final url = avatar;
    if (url == null) {
      return CircleAvatar(child: Text(first ?? '?'));
    }
    return FutureBuilder<(Uri, bool)>(
      future: () async {
        final uri = await url.getThumbnailUri(client, width: 96, height: 96);
        final auth = await client.authenticatedMediaSupported();
        return (uri, auth);
      }(),
      builder: (context, snap) {
        if (snap.hasData) {
          final (uri, auth) = snap.data!;
          return CircleAvatar(
            backgroundImage: NetworkImage(
              uri.toString(),
              headers: auth
                  ? <String, String>{'authorization': 'Bearer ${client.accessToken}'}
                  : null,
            ),
          );
        }
        return CircleAvatar(child: Text(first ?? '?'));
      },
    );
  }
}
