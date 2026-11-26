// 第九十二批（人類 PoC）：通話即時字幕覆蓋層。
// 字幕文字由 whisper_ggml 本機 STT 產生（模型分開下載、保護隱私）。
// ⚠️ PoC 限制：通話中 WebRTC 可能已佔用麥克風 → live STT 可能拿不到音訊；
//    此層只負責「顯示字幕」，成敗由實際音訊來源決定，失敗時显示提示而非崩潰。
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class CallCaptionsOverlay extends StatelessWidget {
  const CallCaptionsOverlay({
    super.key,
    required this.text,
    this.active = false,
  });

  /// 目前字幕文字（即時 STT 結果）。
  final String text;

  /// 是否正在聆聽（false 時顯示「mic 可能已被通話佔用」提示）。
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && !active) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
      child: Text(
        text.isEmpty ? S.t('字幕準備中（麥克風可能被通話佔用）') : text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}
