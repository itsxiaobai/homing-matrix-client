// 第四十六批（人類回報「群組公告還是被當成緊急訊息，應該恢復成一般公告」）
// —— 公告橫幅元件（首頁公告列與聊天室內釘選橫幅**共用同一元件**）。
//
// ## 分流原則（第四十二批確立、第四十六批落實）
//
// | 類型       | 資料來源            | 樣式                  | 前綴   |
// |------------|---------------------|-----------------------|--------|
// | 一般公告   | 聊天室**釘選**訊息  | 中性色＋廣播 icon     | 公告： |
// | 緊急示警   | PWS RSS **官方 feed** | LINE 緊急紅卡片       | （無） |
//
// 兩者資料來源與語意都不同（被動的聊天室公告 vs 官方災害示警），不可混用。
// 因此本元件**只**服務「一般公告」，且**不使用**緊急紅。
//
// 樣式取自 Homing 自身 token（`surfaceContainerHighest` ＋ `kTextSecondary`），
// 不使用任何 LINE 品牌識別。
import 'package:flutter/material.dart';

import 'design_tokens.dart';
import './app_icons_generated.dart'; // 第五十八批：全數圖示槽位化

/// 一般公告橫幅（中性色；非緊急紅）。
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.text,
    this.title,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  /// 公告內容（已去除前綴；本元件自行加上「公告：」）。
  final String text;

  /// 副標（來源聊天室名稱／時間等）；null 則不顯示副標。
  final String? title;

  /// 點擊動作（跳到訊息／開啟聊天室）；null 則不可點。
  final VoidCallback? onTap;

  /// 右側尾端元件（例如「取消釘選」鈕）。
  final Widget? trailing;

  /// 緊湊模式（聊天室內橫幅用；首頁公告列用預設）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      // 中性色＝一般公告；**不使用** errorContainer（那是緊急示警的語意）。
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        dense: dense,
        leading: Icon(AllIcons.campaignOutlined, color: scheme.onSurfaceVariant),
        title: Text(
          '公告：$text',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: (title == null || title!.isEmpty)
            ? null
            : Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: kTextSecondary),
              ),
        onTap: onTap,
        trailing: trailing,
      ),
    );
  }
}
