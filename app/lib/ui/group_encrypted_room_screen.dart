// 2.3 group Megolm E2EE — UI skeleton only
// Agent does NOT author encryption algorithm; through CryptoBridge only.
// 全部 cryptographic procedure delegated to matrix SDK official APIs.
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart'; // 第五十七批：多語言字串層（i18n 全量遷移）
import 'line_style.dart'; // 68e/68f：共用標題語彙

class GroupEncryptedRoomScreen extends StatelessWidget {
  const GroupEncryptedRoomScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: lineTitlePill(context, S.t('加密群組 skeleton'))),
      body: Center(child: Text('Room: $roomId（SDK official E2EE, no agent crypto）')),
    );
  }
}
